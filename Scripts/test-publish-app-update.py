#!/usr/bin/env python3
"""Offline tests for AerialDrop's GitHub update publisher."""

import base64
import copy
import hashlib
import json
import os
import plistlib
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path
from unittest.mock import call, patch

import publish_app_update as publisher
import sparkle_appcast as appcast

TAG = "v1.2.1"
PREVIOUS = "v1.2.0"
COMMIT = "1" * 40
TAG_OBJECT = "3" * 40
PUBLIC_KEY = base64.b64encode(bytes([1]) * 32).decode("ascii")
ZIP = appcast.asset_name(TAG[1:])
ZIP_BYTES = b"official archive"
NOTES = "## Updates\n\n- Add signed updates.\n"
SIGNATURE = base64.b64encode(bytes(64)).decode("ascii")


def feed(tag, archive=ZIP_BYTES, history=(), *, include_digest=True, signature=SIGNATURE):
    root = ET.Element("rss", version="2.0")
    channel = ET.SubElement(root, "channel")
    version = tag[1:]
    release = appcast.Release(version, 42, len(archive), signature, None, 26,
                             frozenset(("arm64", "x86_64")),
                             sha256=hashlib.sha256(archive).hexdigest() if include_digest else None)
    for item in (release, *history):
        appcast.write_item(channel, item, {"min_macos": 26, "max_macos": None,
                                          "architectures": ["arm64", "x86_64"]})
    payload = ET.tostring(root) + b"\n"
    return payload + (f"<!-- sparkle-signatures:\nedSignature: {SIGNATURE}\n"
                      f"length: {len(payload)}\n-->\n").encode("ascii")


def asset(tag, name, payload, *, draft=False):
    url_tag = "untagged-bbeef11498a2d03472f7" if draft else tag
    return {"name": name, "size": len(payload), "state": "uploaded",
            "digest": f"sha256:{hashlib.sha256(payload).hexdigest()}",
            "browser_download_url": f"{publisher.BASE_URL}/{url_tag}/{name}"}


def release(tag, identifier, *, draft=False, include_feed=True):
    return {"tag_name": tag, "id": identifier, "draft": draft, "prerelease": False,
            "published_at": None if draft else "2026-11-19T01:00:00Z",
            "body": NOTES, "assets": [asset(tag, appcast.asset_name(tag[1:]), ZIP_BYTES, draft=draft),
                                      *([asset(tag, publisher.APPCAST, feed(tag), draft=draft)] if include_feed else [])]}


class FakeGitHub:
    def __init__(self, previous=PREVIOUS, include_feed=True):
        self.latest = previous
        self.releases = {previous: release(previous, 1, include_feed=include_feed)}
        self.calls = []
        self.bad_download = False
        self.download_count = 0
        self.change_draft_id_on_upload = False
        self.corrupt_asset_on_upload = False
        self.change_tag_on_upload = False
        self.replace_draft_on_patch = False
        self.withdraw_on_upload = None
        self.commit = COMMIT
        self.annotated = False
        self.downloads = {}
        self.created_draft_lookups = 0
        self.hidden_draft_lookups = 0
        self.draft_lookup_error = False
        self.created_draft_override = {}

    def __call__(self, *args):
        if args[0] == "api":
            if args == ("api", "--hostname", "github.com", f"repos/{publisher.REPOSITORY}/git/ref/tags/{TAG}"):
                target = {"type": "tag", "sha": TAG_OBJECT} if self.annotated else {"type": "commit", "sha": self.commit}
                return json.dumps({"ref": f"refs/tags/{TAG}", "object": target})
            if args == ("api", "--hostname", "github.com", f"repos/{publisher.REPOSITORY}/git/tags/{TAG_OBJECT}"):
                return json.dumps({"object": {"type": "commit", "sha": self.commit}})
            if args == ("api", "--hostname", "github.com", f"{publisher.RELEASES_API}/latest"):
                return json.dumps(self.releases[self.latest])
            if args[:5] == ("api", "--hostname", "github.com", "--method", "PATCH"):
                assert args[5:] == (f"{publisher.RELEASES_API}/2", "-F", "draft=false", "-f", "make_latest=true",
                                    "-f", f"tag_name={TAG}", "-f", f"target_commitish={COMMIT}"), args
                self.calls.append(("patch", TAG, args[5:]))
                if self.replace_draft_on_patch:
                    self.releases[TAG] = release(TAG, 3, draft=True)
                staged = self.releases[TAG]
                if staged["id"] != 2:
                    raise publisher.PublishError("release ID no longer exists")
                assert {item["name"] for item in staged["assets"]} == {ZIP, publisher.APPCAST}
                staged.update(draft=False, published_at="2026-11-19T02:00:00Z")
                for item in staged["assets"]:
                    item["browser_download_url"] = f"{publisher.BASE_URL}/{TAG}/{item['name']}"
                self.latest = TAG
                return json.dumps(staged)
            assert args == ("api", "--hostname", "github.com", "--paginate", "--slurp",
                            f"{publisher.RELEASES_API}?per_page=100"), args
            releases = copy.deepcopy(list(self.releases.values()))
            if TAG in self.releases and any(command == "create" for command, _, _ in self.calls):
                self.created_draft_lookups += 1
                if self.draft_lookup_error:
                    raise publisher.PublishError("GitHub API unavailable")
                if self.created_draft_lookups <= self.hidden_draft_lookups:
                    releases = [entry for entry in releases if entry["tag_name"] != TAG]
                else:
                    next(entry for entry in releases if entry["tag_name"] == TAG).update(
                        self.created_draft_override
                    )
            for entry in releases:
                for item in entry["assets"]:
                    item["download_count"] = self.download_count
            return json.dumps([releases[:1], releases[1:]])
        assert args[0] == "release" and args[3:5] == ("--repo", "github.com/YapWH1208/AerialDrop"), args
        command, tag = args[1:3]
        options = args[5:]
        self.calls.append((command, tag, options))
        if command == "download":
            _, name, _, directory = options
            assert options[0] == "--pattern" and options[2] == "--dir", args
            payload = self.downloads.get((tag, name), feed(tag) if name == publisher.APPCAST else ZIP_BYTES)
            (Path(directory) / name).write_bytes(b"wrong bytes" if self.bad_download else payload)
        elif command == "create":
            assert tag not in self.releases and options[:5] == (
                "--verify-tag", "--draft", "--title", tag, "--notes-file",
            ), args
            assert options[6:] == ("--target", COMMIT), args
            self.releases[tag] = {**release(tag, 2, draft=True), "assets": [],
                                  "body": Path(options[5]).read_text(encoding="utf-8")}
        elif command == "upload":
            draft = self.releases[tag]
            assert draft["draft"] is True, args
            for path in map(Path, options):
                assert path.name not in {item["name"] for item in draft["assets"]}, args
                draft["assets"].append(asset(tag, path.name, path.read_bytes(), draft=True))
            if self.change_draft_id_on_upload:
                draft["id"] += 1
            if self.corrupt_asset_on_upload:
                draft["assets"][-1]["digest"] = f"sha256:{'0' * 64}"
            if self.change_tag_on_upload:
                self.commit = "2" * 40
            if self.withdraw_on_upload:
                del self.releases[self.withdraw_on_upload]
        else:
            raise AssertionError(args)
        return ""


class ReleasePublisherTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.directory = Path(temp.name)
        self.archive = self.directory / ZIP
        self.archive.write_bytes(ZIP_BYTES)
        self.feed = self.directory / publisher.APPCAST
        self.feed.write_bytes(feed(TAG))
        self.notes = self.directory / publisher.NOTES
        self.notes.write_text(NOTES, encoding="utf-8")
        metadata = publisher.predecessor_snapshot(release(PREVIOUS, 1))
        (self.directory / publisher.PREDECESSOR).write_text(json.dumps(metadata), encoding="utf-8")
        self.policy = self.directory / "policy.json"
        self.policy.write_text(json.dumps({"schema_version": 1, "releases": [
            {"version": tag[1:], "min_macos": 26, "max_macos": None,
             "architectures": ["arm64", "x86_64"]}
            for tag in (publisher.LEGACY_TAG, PREVIOUS, TAG, "v1.1.9", "v1.1.8")
        ]}), encoding="utf-8")

    def prepare(self, github, generator):
        with patch.object(publisher, "gh", github), patch.object(publisher, "DEFAULT_POLICY", self.policy), \
                patch.object(publisher, "generate_appcast", generator):
            publisher.prepare(TAG, self.archive, self.notes, self.directory / "sign_update", self.feed)

    def publish(self, github, directory=None):
        with patch.object(publisher, "gh", github):
            publisher.publish(TAG, directory if directory is not None else self.directory, COMMIT)

    def test_gh_does_not_receive_private_key(self):
        with patch.dict(os.environ, {publisher.KEY_ENV: "synthetic-seed", "GH_TOKEN": "synthetic-token"}), \
                patch.object(subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "{}", "")) as run:
            publisher.gh("api", "--hostname", "github.com", publisher.RELEASES_API)
        self.assertNotIn(publisher.KEY_ENV, run.call_args.kwargs["env"])
        self.assertEqual(run.call_args.kwargs["env"]["GH_TOKEN"], "synthetic-token")

    def test_prepare_downloads_verified_feed_and_filters_active_history(self):
        github = FakeGitHub()
        github.download_count = 7
        github.releases["v1.1.9"] = release("v1.1.9", 9, draft=True)
        github.releases["v1.1.8"] = release("v1.1.8", 8)
        github.releases["v1.1.8"]["assets"][0]["state"] = "starter"
        generated = []

        def generate(**kwargs):
            generated.append(kwargs)
            self.assertEqual(kwargs["previous_feed"].read_bytes(), feed(PREVIOUS))
            digest = publisher.local_digest(self.archive)
            self.assertEqual(kwargs["published_archives"], {PREVIOUS[1:]: digest})
            self.assertEqual(kwargs["expected_predecessor"], (PREVIOUS[1:], digest))
            self.assertEqual(kwargs["notes"], NOTES)

        self.prepare(github, generate)
        self.assertEqual(len(generated), 1)
        self.assertEqual([(command, tag) for command, tag, _ in github.calls], [("download", PREVIOUS)])
        self.assertEqual(json.loads((self.directory / publisher.PREDECESSOR).read_text())["tag"], PREVIOUS)

    def test_only_legacy_release_can_omit_appcast(self):
        github = FakeGitHub(publisher.LEGACY_TAG, include_feed=False)
        generated = []
        self.prepare(github, lambda **kwargs: generated.append(kwargs))
        self.assertIsNone(generated[0]["previous_feed"])
        self.assertEqual(github.calls, [])
        with self.assertRaisesRegex(publisher.PublishError, "missing its signed appcast"):
            self.prepare(FakeGitHub(include_feed=False), self.fail)

    def test_prepare_rejects_tampered_feed_and_invalid_latest(self):
        github = FakeGitHub()
        github.bad_download = True
        with self.assertRaisesRegex(publisher.PublishError, "does not match"):
            self.prepare(github, self.fail)
        for override, message in (({"draft": True}, "published stable"),
                                  ({"tag_name": TAG}, "must be older"),
                                  ({"tag_name": "latest"}, "stable v-prefixed")):
            with self.subTest(override=override):
                github.releases[PREVIOUS] = {**release(PREVIOUS, 1), **override}
                with self.assertRaisesRegex(ValueError, message):
                    self.prepare(github, self.fail)

    def test_publish_accepts_temporary_draft_urls_and_rerun_matches_artifact(self):
        github = FakeGitHub()
        github.annotated = True
        self.publish(github)
        self.publish(github)
        self.assertEqual([command for command, _, _ in github.calls], ["create", "upload", "patch"])
        self.assertEqual([Path(path).name for path in github.calls[1][2]], [ZIP, publisher.APPCAST])

    def test_new_draft_waits_for_visibility_before_upload(self):
        github = FakeGitHub()
        github.hidden_draft_lookups = 2
        with patch.object(publisher.time, "sleep") as sleep:
            self.publish(github)
        self.assertEqual(sleep.call_args_list, [call(1), call(2)])
        # Three visibility checks and two later publication checks.
        self.assertEqual(github.created_draft_lookups, 5)
        self.assertEqual([command for command, _, _ in github.calls], ["create", "upload", "patch"])

    def test_new_draft_visibility_exhaustion_can_be_resumed(self):
        github = FakeGitHub()
        github.hidden_draft_lookups = 5
        with patch.object(publisher.time, "sleep") as sleep:
            with self.assertRaisesRegex(publisher.PublishError, "original signed workflow artifact"):
                self.publish(github)
        self.assertEqual(sleep.call_args_list, [call(1), call(2), call(4), call(8)])
        self.assertEqual(github.created_draft_lookups, 5)
        self.assertEqual([command for command, _, _ in github.calls], ["create"])
        self.assertTrue(github.releases[TAG]["draft"])
        with patch.object(publisher.time, "sleep") as sleep:
            self.publish(github)
        sleep.assert_not_called()
        self.assertEqual([command for command, _, _ in github.calls], ["create", "upload", "patch"])

    def test_visible_invalid_new_draft_fails_without_retry(self):
        for override, message in (({"prerelease": True}, "stable draft"),
                                  ({"id": 0}, "invalid GitHub release ID")):
            with self.subTest(override=override):
                github = FakeGitHub()
                github.created_draft_override = override
                with patch.object(publisher.time, "sleep") as sleep:
                    with self.assertRaisesRegex(publisher.PublishError, message):
                        self.publish(github)
                sleep.assert_not_called()
                self.assertEqual(github.created_draft_lookups, 1)
                self.assertEqual([command for command, _, _ in github.calls], ["create"])

    def test_new_draft_catalogue_api_error_fails_without_retry(self):
        github = FakeGitHub()
        github.draft_lookup_error = True
        with patch.object(publisher.time, "sleep") as sleep:
            with self.assertRaisesRegex(publisher.PublishError, "GitHub API unavailable"):
                self.publish(github)
        sleep.assert_not_called()
        self.assertEqual(github.created_draft_lookups, 1)
        self.assertEqual([command for command, _, _ in github.calls], ["create"])

    def test_public_rerun_rejects_bytes_that_differ_from_retained_artifact(self):
        github = FakeGitHub()
        github.releases[TAG] = release(TAG, 2)
        for name, altered in ((ZIP, b"+" * len(ZIP_BYTES)), (publisher.APPCAST, b"changed feed")):
            with self.subTest(asset=name):
                github.releases[TAG] = release(TAG, 2)
                assets = github.releases[TAG]["assets"]
                index = next(index for index, item in enumerate(assets) if item["name"] == name)
                assets[index] = asset(TAG, name, altered)
                with self.assertRaisesRegex(publisher.PublishError, "does not match the prepared release assets"):
                    self.publish(github)
        self.assertEqual(github.calls, [])

    def test_resume_uploads_only_missing_asset(self):
        github = FakeGitHub()
        github.releases[TAG] = release(TAG, 2, draft=True, include_feed=False)
        self.publish(github)
        self.assertEqual([command for command, _, _ in github.calls], ["upload", "patch"])
        self.assertEqual(github.calls[0][2], (str(self.feed),))

    def test_a_new_predecessor_requires_fresh_signing_before_mutation(self):
        github = FakeGitHub()
        prepared_against = publisher.predecessor_snapshot(release(publisher.LEGACY_TAG, 1, include_feed=False))
        (self.directory / publisher.PREDECESSOR).write_text(json.dumps(prepared_against), encoding="utf-8")
        with self.assertRaisesRegex(publisher.PublishError, "changed since signing"):
            self.publish(github)
        self.assertEqual(github.calls, [])

    def test_rejects_invalid_draft_before_mutation_and_checks_identity_after_upload(self):
        github = FakeGitHub()
        draft = release(TAG, 2, draft=True, include_feed=False)
        github.releases[TAG] = copy.deepcopy(draft)
        github.releases[TAG]["assets"][0] = asset(TAG, ZIP, b"different archive")
        with self.assertRaisesRegex(publisher.PublishError, "original signed workflow artifact"):
            self.publish(github)
        self.assertEqual(github.calls, [])
        github.releases[TAG] = draft
        github.change_draft_id_on_upload = True
        with self.assertRaisesRegex(publisher.PublishError, "changed its GitHub release ID"):
            self.publish(github)
        self.assertEqual([command for command, _, _ in github.calls], ["upload"])

    def test_publish_revalidates_uploaded_digest_before_publication(self):
        github = FakeGitHub()
        github.corrupt_asset_on_upload = True
        with self.assertRaisesRegex(publisher.PublishError, "different bytes for appcast.xml"):
            self.publish(github)
        self.assertEqual([command for command, _, _ in github.calls], ["create", "upload"])
        self.assertTrue(github.releases[TAG]["draft"])

    def test_publish_refuses_moved_tag_or_replaced_draft(self):
        github = FakeGitHub()
        github.change_tag_on_upload = True
        with self.assertRaisesRegex(publisher.PublishError, "no longer points"):
            self.publish(github)
        self.assertEqual([command for command, _, _ in github.calls], ["create", "upload"])
        self.assertTrue(github.releases[TAG]["draft"])

        github = FakeGitHub()
        github.replace_draft_on_patch = True
        with self.assertRaisesRegex(publisher.PublishError, "release ID no longer exists"):
            self.publish(github)
        self.assertTrue(github.releases[TAG]["draft"])
        self.assertEqual(github.latest, PREVIOUS)

    def test_publish_rejects_retained_archive_changed_during_staging(self):
        previous_tag = "v1.1.9"
        self.feed.write_bytes(feed(TAG, history=(appcast.parse_history(feed(previous_tag))[0],)))
        github = FakeGitHub()
        github.releases[previous_tag] = release(previous_tag, 9)
        github.withdraw_on_upload = previous_tag
        with self.assertRaisesRegex(publisher.PublishError, r"retained ZIP for v1\.1\.9 changed or is unavailable"):
            self.publish(github)
        self.assertEqual([command for command, _, _ in github.calls], ["create", "upload"])
        self.assertTrue(github.releases[TAG]["draft"])

    def test_status_checks_both_published_slots(self):
        self.assertIsNone(publisher.published_digests(TAG, None))
        self.assertIsNone(publisher.published_digests(TAG, release(TAG, 2, draft=True)))
        self.assertEqual(set(publisher.published_digests(TAG, release(TAG, 2))), {ZIP, publisher.APPCAST})
        with self.assertRaisesRegex(publisher.PublishError, "missing appcast.xml"):
            publisher.published_digests(TAG, release(TAG, 2, include_feed=False))
        metadata = release(TAG, 2)
        metadata["assets"][1]["browser_download_url"] += "?other"
        with self.assertRaisesRegex(publisher.PublishError, "invalid GitHub asset metadata"):
            publisher.published_digests(TAG, metadata)

    def test_status_verifies_public_release_and_current_identity(self):
        github = FakeGitHub()
        with patch.object(publisher, "gh", github), patch.object(publisher, "verify_public_release") as verify:
            self.assertFalse(publisher.release_status(TAG, COMMIT, PUBLIC_KEY))
            verify.assert_not_called()
            github.releases[TAG] = release(TAG, 2)
            self.assertTrue(publisher.release_status(TAG, COMMIT, PUBLIC_KEY))
            verify.assert_called_once_with(TAG, publisher.published_digests(TAG, github.releases[TAG]), PUBLIC_KEY)
            verify.side_effect = lambda *_: github.releases[TAG].update(id=3)
            with self.assertRaisesRegex(publisher.PublishError, "changed during signature verification"):
                publisher.release_status(TAG, COMMIT, PUBLIC_KEY)


@unittest.skipUnless(os.environ.get("SPARKLE_SIGN_TOOL"), "set SPARKLE_SIGN_TOOL to run Sparkle")
class PublicReleaseSignatureTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.directory = Path(temp.name).resolve()
        self.signer = str(Path(os.environ["SPARKLE_SIGN_TOOL"]).resolve())
        self.seed = base64.b64encode(os.urandom(32)).decode("ascii")
        self.public_key = appcast.run_with_key(
            ["swift", "-module-cache-path", str(self.directory / "modules"), "-e", appcast.DERIVE_PUBLIC_KEY],
            self.seed, self.directory, "test public-key derivation",
        ).strip().decode("ascii")

    def sign(self, *args):
        return appcast.run_with_key(
            [self.signer, "--ed-key-file", "-", *args], self.seed, self.directory, "test signing",
        )

    def signed_assets(self, *, embedded_key=None, feed_tag=TAG, include_digest=True):
        archive = self.directory / ZIP
        with zipfile.ZipFile(archive, "w") as bundle:
            bundle.writestr(appcast.INFO_PATH, plistlib.dumps({
                **appcast.REQUIRED_SETTINGS,
                "CFBundleIdentifier": "com.yapwh.aerialdrop",
                "CFBundleShortVersionString": TAG[1:],
                "CFBundleVersion": "42",
                "LSMinimumSystemVersion": "26.0",
                "SUPublicEDKey": embedded_key or self.public_key,
            }))
        archive_bytes = archive.read_bytes()
        signature = self.sign("-p", str(archive)).strip().decode("ascii")
        fixture = feed(feed_tag, archive_bytes, include_digest=include_digest, signature=signature)
        payload, _ = appcast.split_signed_feed(fixture)
        signed_feed = self.directory / publisher.APPCAST
        signed_feed.write_bytes(payload)
        self.sign(str(signed_feed))
        return archive_bytes, signed_feed.read_bytes()

    def status(self, archive, signed_feed, public_key):
        github = FakeGitHub()
        github.downloads = {(TAG, ZIP): archive, (TAG, publisher.APPCAST): signed_feed}
        github.releases[TAG] = {**release(TAG, 2),
                               "assets": [asset(TAG, name, payload) for (_, name), payload in github.downloads.items()]}
        with patch.object(publisher, "gh", github):
            return publisher.release_status(TAG, COMMIT, public_key)

    def test_verifies_public_assets_and_rejects_changed_feed_or_key(self):
        archive, signed_feed = self.signed_assets()
        self.assertTrue(self.status(archive, signed_feed, self.public_key))
        changed_feed = signed_feed.replace(b"AerialDrop 1.2.1", b"AerialXrop 1.2.1")
        self.assertNotEqual(changed_feed, signed_feed)
        with self.assertRaisesRegex(ValueError, "appcast signature verification failed"):
            self.status(archive, changed_feed, self.public_key)
        with self.assertRaisesRegex(ValueError, "appcast signature verification failed"):
            self.status(archive, signed_feed, PUBLIC_KEY)

    def test_rejects_modified_legacy_zip_and_valid_signatures_for_the_wrong_identity(self):
        archive, signed_feed = self.signed_assets(include_digest=False)
        self.assertTrue(self.status(archive, signed_feed, self.public_key))
        changed_archive = archive[:-1] + bytes([archive[-1] ^ 1])
        with self.assertRaisesRegex(ValueError, "ZIP signature verification failed"):
            self.status(changed_archive, signed_feed, self.public_key)

        archive, signed_feed = self.signed_assets(embedded_key=PUBLIC_KEY)
        with self.assertRaisesRegex(publisher.PublishError, "ZIP build or update key"):
            self.status(archive, signed_feed, self.public_key)

        archive, signed_feed = self.signed_assets(feed_tag=PREVIOUS)
        with self.assertRaisesRegex(publisher.PublishError, "must start with " + TAG):
            self.status(archive, signed_feed, self.public_key)


if __name__ == "__main__":
    unittest.main()
