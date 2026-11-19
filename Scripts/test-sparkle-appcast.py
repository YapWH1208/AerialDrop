#!/usr/bin/env python3
"""Regression checks for the release ZIP and signed Sparkle appcast."""

import base64
import os
import plistlib
import re
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path
from unittest.mock import patch

import sparkle_appcast as appcast


# The mocked signer uses valid encodings as placeholders for its key inputs.
TEST_SEED = base64.b64encode(os.urandom(32)).decode("ascii")
TEST_PUBLIC_KEY = base64.b64encode(bytes([1]) * 32).decode("ascii")
FIXTURE_SIGNATURE = b"A" * 86 + b"=="


def declaration(version, minimum=26, maximum=None, architectures=("arm64",)):
    return {
        "version": version,
        "min_macos": minimum,
        "max_macos": maximum,
        "architectures": list(architectures),
    }


def with_signing_block(payload):
    return (
        payload + b"<!-- sparkle-signatures:\nedSignature: " + FIXTURE_SIGNATURE
        + f"\nlength: {len(payload)}\n-->\n".encode("ascii")
    )


class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.output = self.directory / "appcast.xml"

    def bundle(self, version="1.0.0", build="1", minimum=26, overrides=None):
        archive = self.directory / appcast.asset_name(version)
        info = {
            **appcast.REQUIRED_SETTINGS,
            "CFBundleIdentifier": "com.yapwh.aerialdrop",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build,
            "LSMinimumSystemVersion": f"{minimum}.0",
            "SUPublicEDKey": TEST_PUBLIC_KEY,
            **(overrides or {}),
        }
        with zipfile.ZipFile(archive, "w") as bundle:
            bundle.writestr(appcast.INFO_PATH, plistlib.dumps(info))
        return archive

    def generate(self, version="1.0.0", archive=None, records=None, **options):
        appcast.generate_appcast(
            tag=f"v{version}",
            archive=archive if archive is not None else self.bundle(version),
            output=self.output,
            sign_tool=Path(os.environ.get("SPARKLE_SIGN_TOOL", "sign_update")),
            policy={"schema_version": 1, "releases": records or [declaration(version)]},
            key=options.pop("key", TEST_SEED),
            **options,
        )

    def fake_signer(self, command, key, working_directory, operation):
        self.assertEqual(key, TEST_SEED)
        if operation == "Ed25519 public-key derivation":
            return TEST_PUBLIC_KEY.encode("ascii")
        self.assertEqual(command[1:3], ["--ed-key-file", "-"])
        self.assertTrue(working_directory.is_dir())
        if operation == "release ZIP signing":
            return FIXTURE_SIGNATURE
        if operation == "appcast signing":
            path = Path(command[-1])
            path.write_bytes(with_signing_block(path.read_bytes()))
        return b""

    def test_rejects_zips_with_invalid_bundle_metadata(self):
        invalid = {
            "CFBundleIdentifier": "com.example.other",
            "CFBundleShortVersionString": "1.1.0",
            "CFBundleVersion": "01",
            "LSMinimumSystemVersion": "27.0",
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUVerifyUpdateBeforeExtraction": False,
            "SURequireSignedFeed": False,
            "SUAllowsAutomaticUpdates": True,
            "SUSignedFeedFailureExpirationInterval": False,
            "SUPublicEDKey": "bogus",
        }
        for name, value in invalid.items():
            with self.subTest(name=name), self.assertRaisesRegex(appcast.AppcastError, name):
                appcast.read_bundle(self.bundle(overrides={name: value}), "1.0.0", 26)
        with self.assertRaisesRegex(appcast.AppcastError, "filename"):
            appcast.read_bundle(self.bundle(), "1.0.1", 26)

    def test_rejects_malformed_or_mismatched_private_key(self):
        malformed = "this is not a key"
        with patch.object(appcast, "run_with_key") as run:
            with self.assertRaisesRegex(appcast.AppcastError, appcast.KEY_ENV) as context:
                self.generate(key=malformed)
            self.assertNotIn(malformed, str(context.exception))
            run.assert_not_called()
        different_key = base64.b64encode(bytes(32)).decode("ascii")
        with patch.object(appcast, "run_with_key", side_effect=self.fake_signer):
            archive = self.bundle(overrides={"SUPublicEDKey": different_key})
            with self.assertRaisesRegex(appcast.AppcastError, "does not match"):
                self.generate(archive=archive)
        self.assertFalse(self.output.exists())

    def test_keeps_child_diagnostics_and_private_key_out_of_output(self):
        secret = "could be echoed by a failed subprocess"
        failure = subprocess.CompletedProcess(["tool"], 1, secret.encode(), secret.encode())
        with patch.dict(os.environ, {appcast.KEY_ENV: secret}):
            with patch.object(appcast.subprocess, "run", return_value=failure) as run:
                with self.assertRaisesRegex(appcast.AppcastError, r"^signing failed$"):
                    appcast.run_with_key(["tool"], secret, self.directory, "signing")
        self.assertNotIn(appcast.KEY_ENV, run.call_args.kwargs["env"])
        self.assertEqual(run.call_args.kwargs["input"], (secret + "\n").encode("ascii"))
        self.assertTrue(run.call_args.kwargs["capture_output"])

    def test_policy_history_and_markdown(self):
        with patch.object(appcast, "run_with_key", side_effect=self.fake_signer):
            self.generate(notes="First **release** & archive.")
            self.generate(
                version="1.1.0",
                archive=self.bundle("1.1.0", "2", minimum=27),
                records=[
                    declaration("1.0.0", maximum=26),
                    declaration("1.1.0", minimum=27, architectures=("arm64", "x86_64")),
                ],
                previous_feed=self.output,
            )
            root = ET.parse(self.output)
            current, previous = root.findall("./channel/item")
            self.assertEqual(current.findtext(appcast.sparkle("minimumSystemVersion")), "27.0")
            self.assertIsNone(current.find(appcast.sparkle("hardwareRequirements")))
            self.assertEqual(previous.findtext(appcast.sparkle("hardwareRequirements")), "arm64")
            maximum = previous.findtext(appcast.sparkle("maximumSystemVersion"))
            self.assertEqual(maximum, f"26.{2**63 - 1}.{2**63 - 1}")
            self.assertLess((26, 99, 99), tuple(map(int, maximum.split("."))))
            self.assertGreater((27, 0, 0), tuple(map(int, maximum.split("."))))
            self.assertEqual(previous.findtext("description"), "First **release** & archive.")
            self.assertEqual(previous.find("description").get(appcast.sparkle("format")), "markdown")
            self.generate(
                version="1.2.0", archive=self.bundle("1.2.0", "3"), previous_feed=self.output,
            )
            self.assertEqual([r.version for r in appcast.parse_history(self.output.read_bytes())],
                             ["1.2.0"])

    def test_rejects_policy_that_widens_signed_history(self):
        with patch.object(appcast, "run_with_key", side_effect=self.fake_signer):
            self.generate(archive=self.bundle(minimum=27), records=[declaration("1.0.0", 27)])
            original = self.output.read_bytes()
            widened = [
                declaration("1.0.0", 26),
                declaration("1.0.0", 27, architectures=("arm64", "x86_64")),
            ]
            for record in widened:
                with self.subTest(record=record):
                    with self.assertRaisesRegex(appcast.AppcastError, "widens signed history"):
                        self.generate(
                            version="1.1.0", archive=self.bundle("1.1.0", "2"),
                            records=[record, declaration("1.1.0")], previous_feed=self.output,
                        )
            self.assertEqual(self.output.read_bytes(), original)

    def test_predecessor_must_match_and_withdrawn_assets_are_omitted(self):
        with patch.object(appcast, "run_with_key", side_effect=self.fake_signer):
            old_zip = self.bundle()
            self.generate(archive=old_zip)
            original = self.output.read_bytes()
            options = dict(
                version="1.1.0", archive=self.bundle("1.1.0", "2"),
                records=[declaration("1.0.0"), declaration("1.1.0")],
                previous_feed=self.output,
            )
            with self.assertRaisesRegex(appcast.AppcastError, "latest published release ZIP"):
                self.generate(**options, expected_predecessor=("1.0.0", 1))
            self.assertEqual(self.output.read_bytes(), original)
            self.generate(**options, expected_predecessor=("1.0.0", old_zip.stat().st_size),
                          published_archives={})
            self.assertEqual([r.version for r in appcast.parse_history(self.output.read_bytes())], ["1.1.0"])

    def test_rejects_unsupported_architectures_and_build_ties(self):
        with patch.object(appcast, "run_with_key", side_effect=self.fake_signer):
            with self.assertRaisesRegex(appcast.AppcastError, "cannot represent architectures"):
                self.generate(records=[declaration("1.0.0", architectures=("x86_64",))])
            self.generate()
            prior_data = self.output.read_bytes()
            with self.assertRaisesRegex(appcast.AppcastError, "tie or downgrade"):
                self.generate(version="1.1.0", previous_feed=self.output)
            self.assertEqual(self.output.read_bytes(), prior_data)

    def test_rejects_invalid_history_item_fields(self):
        with patch.object(appcast, "run_with_key", side_effect=self.fake_signer):
            self.generate()
            payload = self.output.read_bytes().split(b"<!-- sparkle-signatures:", 1)[0]
            changes = [
                (b"/v1.0.0/", b"/v2.0.0/", "unexpected enclosure"),
                (b'length="' + re.search(rb'length="([0-9]+)"', payload)[1] + b'"',
                 b'length="0"', "ZIP length"),
                (FIXTURE_SIGNATURE, b"bad", "ZIP Ed25519 signature"),
                (b"</channel>", re.search(rb"<item>.*?</item>", payload, re.S)[0]
                 + b"</channel>", "duplicate or non-increasing"),
            ]
            for original, replacement, message in changes:
                with self.subTest(message=message):
                    self.output.write_bytes(with_signing_block(payload.replace(original, replacement)))
                    with self.assertRaisesRegex(appcast.AppcastError, message):
                        self.generate(
                            version="1.1.0", archive=self.bundle("1.1.0", "2"),
                            previous_feed=self.output,
                        )
            invalid_length = with_signing_block(payload).replace(b"length: ", b"length: 9")
            with self.assertRaisesRegex(appcast.AppcastError, "signed length"):
                appcast.parse_history(invalid_length)

    @unittest.skipUnless(os.environ.get("SPARKLE_SIGN_TOOL"), "set SPARKLE_SIGN_TOOL to run Sparkle")
    def test_real_signatures_and_tampered_history(self):
        seed, public_key = subprocess.check_output([
            "swift", "-module-cache-path", str(self.directory / "module-cache"), "-e", """
            import CryptoKit
            import Foundation
            let key = Curve25519.Signing.PrivateKey()
            print(key.rawRepresentation.base64EncodedString())
            print(key.publicKey.rawRepresentation.base64EncodedString())
            """,
        ], text=True).splitlines()
        overrides = {"SUPublicEDKey": public_key}
        self.generate(archive=self.bundle(overrides=overrides), notes="Release notes", key=seed)
        original = self.output.read_bytes()
        self.assertEqual(appcast.parse_history(original)[0].version, "1.0.0")
        previous = self.directory / "previous.xml"
        previous.write_bytes(original)
        options = dict(
            version="1.1.0", archive=self.bundle("1.1.0", "2", overrides=overrides),
            records=[declaration("1.0.0"), declaration("1.1.0")], previous_feed=previous, key=seed,
        )
        self.generate(**options)
        signed = self.output.read_bytes()
        signed_releases = appcast.parse_history(signed)
        self.assertEqual(len(signed_releases), 2)
        previous.write_bytes(original.replace(b"Release notes", b"Release edits"))
        with self.assertRaisesRegex(appcast.AppcastError, "previous appcast signature verification"):
            self.generate(**options)
        self.assertEqual(self.output.read_bytes(), signed)

        archive = options["archive"]
        archive.write_bytes(archive.read_bytes() + b"changed after signing")
        with self.assertRaisesRegex(appcast.AppcastError, "modified ZIP verification failed"):
            appcast.run_with_key([
                os.environ["SPARKLE_SIGN_TOOL"], "--ed-key-file", "-", "--verify",
                str(archive), signed_releases[0].signature,
            ], seed, self.directory, "modified ZIP verification")


if __name__ == "__main__":
    unittest.main()
