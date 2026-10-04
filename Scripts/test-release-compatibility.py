#!/usr/bin/env python3
"""Offline contract checks for release compatibility selection."""

import copy
import json
import plistlib
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "Scripts"))

from release_compatibility import (  # noqa: E402
    CompatibilityError,
    _source_minimum,
    _source_version,
    resolve_release,
    validate_policy,
    validate_source,
    version_key,
)


FIXTURE = json.loads((ROOT / "Tests/DistributionFixtures/compatibility.json").read_text())


class CompatibilityTests(unittest.TestCase):
    def test_current_policy_and_source(self):
        policy = json.loads((ROOT / "docs/release-compatibility.json").read_text())
        validate_source(policy)
        with self.assertRaisesRegex(CompatibilityError, "does not match source"):
            validate_source(policy, tag="v0.0.0")
        versions = {entry["version"] for entry in policy["releases"]}
        self.assertTrue({
            "0.6.1", "1.0.0", *(f"1.1.{minor}" for minor in range(10))
        }.issubset(versions))

    def test_shared_fixture(self):
        for case in FIXTURE["cases"]:
            with self.subTest(case=case["name"]):
                arguments = (
                    FIXTURE["policy"],
                    FIXTURE["catalogues"][case["catalogue"]],
                    case["macos"],
                    case["arch"],
                )
                if case["expected_version"] is None:
                    with self.assertRaises(CompatibilityError):
                        resolve_release(*arguments, version=case.get("version"))
                else:
                    selected = resolve_release(*arguments, version=case.get("version"))
                    self.assertEqual(selected["version"], case["expected_version"])
                    self.assertEqual(selected["asset"]["sha256"], "a" * 64)

    def test_numeric_order_and_stable_version_bounds(self):
        self.assertGreater(version_key("1.1.10"), version_key("1.1.9"))
        for version in ("v1.1.9", "1.01.0", "1.1", "1.1.0-beta", "1000000.0.0", "1.1.00", "9" * 10000 + ".0.0"):
            with self.subTest(version=version), self.assertRaises(CompatibilityError):
                version_key(version)

    def test_malformed_policy(self):
        original = FIXTURE["policy"]
        mutations = [
            lambda p: p.update(schema_version=True),
            lambda p: p.update(schema_version=2),
            lambda p: p.update(releases=[]),
            lambda p: p["releases"].append(copy.deepcopy(p["releases"][0])),
            lambda p: p["releases"][0].update(min_macos=25),
            lambda p: p["releases"][0].update(min_macos=True),
            lambda p: p["releases"][0].update(max_macos=25),
            lambda p: p["releases"][0].update(architectures=[]),
            lambda p: p["releases"][0].update(architectures=["arm64", "arm64"]),
            lambda p: p["releases"][0].update(architectures=["ppc"]),
            lambda p: p["releases"][0].update(version="01.1.0"),
            lambda p: p.update(extra=True),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(mutation=index):
                policy = copy.deepcopy(original)
                mutate(policy)
                with self.assertRaises(CompatibilityError):
                    validate_policy(policy)

    def test_malformed_catalogue(self):
        for catalogue in (None, {}, [None], [{}], [
            FIXTURE["catalogues"]["base"][0],
            FIXTURE["catalogues"]["base"][0],
        ]):
            with self.subTest(catalogue=catalogue), self.assertRaises(CompatibilityError):
                resolve_release(FIXTURE["policy"], catalogue, 26, "arm64")

    def test_invalid_asset_details_are_not_selected(self):
        release = copy.deepcopy(FIXTURE["catalogues"]["base"][1])
        for mutation in (
            {"size": 0},
            {"size": True},
            {"size": "100"},
            {"digest": "sha256:" + "x" * 64},
            {"browser_download_url": "https://example.invalid/other.zip"},
        ):
            with self.subTest(mutation=mutation):
                broken = copy.deepcopy(release)
                broken["assets"][0].update(mutation)
                with self.assertRaises(CompatibilityError):
                    resolve_release(FIXTURE["policy"], [broken], 26, "arm64")

    def test_bundle_checks_minimum_and_architecture(self):
        policy = json.loads((ROOT / "docs/release-compatibility.json").read_text())
        source_version = _source_version(ROOT / "Sources/AerialDrop/AppVersion.swift")
        minimum = _source_minimum(ROOT / "Package.swift")
        record = next(record for record in policy["releases"] if record["version"] == source_version)
        with tempfile.TemporaryDirectory() as directory:
            bundle = Path(directory) / "AerialDrop.app"
            contents = bundle / "Contents"
            contents.mkdir(parents=True)
            info = {
                "CFBundleShortVersionString": source_version,
                "LSMinimumSystemVersion": f"{minimum}.0",
            }
            plist = contents / "Info.plist"

            def write_plist():
                with plist.open("wb") as handle:
                    plistlib.dump(info, handle)

            write_plist()
            with patch("release_compatibility.subprocess.check_output", return_value=" ".join(record["architectures"]) + "\n"):
                validate_source(policy, bundle=bundle)
                info["LSMinimumSystemVersion"] = "999.0"
                write_plist()
                with self.assertRaisesRegex(CompatibilityError, "bundle macOS minimum"):
                    validate_source(policy, bundle=bundle)

            info["LSMinimumSystemVersion"] = f"{minimum}.0"
            write_plist()
            with patch("release_compatibility.subprocess.check_output", return_value="ppc\n"):
                with self.assertRaisesRegex(CompatibilityError, "bundle architectures"):
                    validate_source(policy, bundle=bundle)


if __name__ == "__main__":
    unittest.main()
