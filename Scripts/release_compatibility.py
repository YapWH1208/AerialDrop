#!/usr/bin/env python3
"""Validate AerialDrop compatibility declarations and resolve official releases.

The installer and website use the same JSON contract. This maintenance module
provides strict source/release checks without adding a runtime dependency to
the macOS installer.
"""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_POLICY = ROOT / "docs" / "release-compatibility.json"
VERSION_RE = re.compile(r"(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\Z")
DIGEST_RE = re.compile(r"sha256:([0-9a-fA-F]{64})\Z")
ARCHITECTURES = frozenset(("arm64", "x86_64"))
BASE_URL = "https://github.com/YapWH1208/AerialDrop/releases/download"


class CompatibilityError(ValueError):
    """Policy, release metadata, or compatibility selection is invalid."""


def version_key(version: str) -> tuple[int, int, int]:
    """Return a bounded numeric stable version tuple, excluding a v prefix."""
    if not isinstance(version, str) or (match := VERSION_RE.fullmatch(version)) is None:
        raise CompatibilityError(f"invalid stable version: {version!r}")
    parts = tuple(int(part) for part in match.groups())
    return parts


def _major(value: Any, label: str) -> int:
    if type(value) is not int or not 26 <= value <= 999:
        raise CompatibilityError(f"{label} must be an integer from 26 through 999")
    return value


def validate_policy(policy: Any) -> dict[str, Any]:
    """Validate schema and every record; return the original policy on success."""
    if not isinstance(policy, dict) or set(policy) != {"schema_version", "releases"}:
        raise CompatibilityError("policy must contain only schema_version and releases")
    if type(policy["schema_version"]) is not int or policy["schema_version"] != 1:
        raise CompatibilityError("unsupported compatibility policy schema_version")
    records = policy["releases"]
    if not isinstance(records, list) or not records:
        raise CompatibilityError("policy releases must be a nonempty array")
    versions: set[str] = set()
    for index, record in enumerate(records):
        label = f"releases[{index}]"
        if not isinstance(record, dict) or set(record) != {
            "version", "min_macos", "max_macos", "architectures"
        }:
            raise CompatibilityError(f"{label} has invalid fields")
        version = record["version"]
        version_key(version)
        if version in versions:
            raise CompatibilityError(f"duplicate compatibility version: {version}")
        versions.add(version)
        minimum = _major(record["min_macos"], f"{label}.min_macos")
        maximum = record["max_macos"]
        if maximum is not None and _major(maximum, f"{label}.max_macos") < minimum:
            raise CompatibilityError(f"{label}.max_macos is below min_macos")
        architectures = record["architectures"]
        if (not isinstance(architectures, list) or not architectures
                or any(not isinstance(arch, str) or arch not in ARCHITECTURES
                       for arch in architectures)
                or len(architectures) != len(set(architectures))):
            raise CompatibilityError(f"{label}.architectures must contain unique supported architectures")
    return policy


def compatible(record: dict[str, Any], macos: int, arch: str) -> bool:
    """Check one already validated declaration against a machine."""
    _major(macos, "macos")
    if arch not in ARCHITECTURES:
        raise CompatibilityError(f"unsupported architecture: {arch!r}")
    return (record["min_macos"] <= macos
            and (record["max_macos"] is None or macos <= record["max_macos"])
            and arch in record["architectures"])


def _validated_asset(release: dict[str, Any], version: str) -> dict[str, Any] | None:
    """Return the sole exact official ZIP asset, or exclude the candidate."""
    assets = release.get("assets")
    if not isinstance(assets, list):
        return None
    name = f"AerialDrop-{version}-macOS.zip"
    matches = [asset for asset in assets if isinstance(asset, dict) and asset.get("name") == name]
    if len(matches) != 1:
        return None
    asset = matches[0]
    digest = asset.get("digest")
    url = f"{BASE_URL}/v{version}/{name}"
    if (not isinstance(digest, str) or DIGEST_RE.fullmatch(digest) is None
            or type(asset.get("size")) is not int or asset["size"] <= 0
            or asset.get("browser_download_url") != url):
        return None
    return {
        "name": name,
        "url": url,
        "sha256": digest[7:].lower(),
        "size": asset["size"],
    }


def resolve_release(
    policy: Any, catalogue: Any, macos: int, arch: str, version: str | None = None
) -> dict[str, Any]:
    """Select highest compatible published release or verify an exact pin.

    GitHub's /repos/YapWH1208/AerialDrop/releases API array is the catalogue.
    Incomplete or unpublished candidates are excluded; malformed catalogue
    structure and duplicate release tags fail explicitly.
    """
    validate_policy(policy)
    _major(macos, "macos")
    if arch not in ARCHITECTURES:
        raise CompatibilityError(f"unsupported architecture: {arch!r}")
    if version is not None:
        version_key(version)
    if not isinstance(catalogue, list):
        raise CompatibilityError("release catalogue must be an array")
    declarations = {record["version"]: record for record in policy["releases"]}
    if version is not None and version not in declarations:
        raise CompatibilityError(f"version {version} is not declared in the compatibility policy")
    if version is not None and not compatible(declarations[version], macos, arch):
        raise CompatibilityError(f"version {version} is incompatible with macOS {macos} on {arch}")
    candidates: list[dict[str, Any]] = []
    seen_tags: set[str] = set()
    for index, release in enumerate(catalogue):
        if not isinstance(release, dict):
            raise CompatibilityError(f"release catalogue entry {index} must be an object")
        tag = release.get("tag_name")
        if not isinstance(tag, str):
            raise CompatibilityError(f"release catalogue entry {index} has no tag_name")
        if tag in seen_tags:
            raise CompatibilityError(f"duplicate release catalogue tag: {tag}")
        seen_tags.add(tag)
        if not tag.startswith("v"):
            continue
        candidate_version = tag[1:]
        try:
            version_key(candidate_version)
        except CompatibilityError:
            continue
        record = declarations.get(candidate_version)
        if record is None or (version is not None and candidate_version != version):
            continue
        if (release.get("draft") is not False or release.get("prerelease") is not False
                or not isinstance(release.get("published_at"), str)
                or not release["published_at"]):
            continue
        if not compatible(record, macos, arch):
            continue
        asset = _validated_asset(release, candidate_version)
        if asset is None:
            continue
        candidates.append({"version": candidate_version, "tag": tag, "asset": asset})
    if not candidates:
        if version is not None:
            raise CompatibilityError(f"version {version} has no valid published official ZIP release")
        raise CompatibilityError(f"no compatible published release for macOS {macos} on {arch}")
    return max(candidates, key=lambda item: version_key(item["version"]))


def _source_version(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    match = re.search(r'static let shortVersion\s*=\s*"([^"]+)"', text)
    if match is None:
        raise CompatibilityError(f"cannot read shortVersion in {path}")
    version_key(match.group(1))
    return match.group(1)


def _source_minimum(path: Path) -> int:
    text = path.read_text(encoding="utf-8")
    match = re.search(r'\.macOS\("([0-9]+)\.([0-9]+)"\)', text)
    if match is None:
        raise CompatibilityError(f"cannot read macOS platform in {path}")
    minimum = _major(int(match.group(1)), "Package.swift macOS minimum")
    if int(match.group(2)) != 0:
        raise CompatibilityError("policy records major macOS versions; Package.swift must use .0")
    return minimum


def validate_source(policy: Any, tag: str | None = None, bundle: Path | None = None) -> None:
    """Check current source and optional release tag/bundle against its policy row."""
    validate_policy(policy)
    source_version = _source_version(ROOT / "Sources/AerialDrop/AppVersion.swift")
    if tag is not None and tag != f"v{source_version}":
        raise CompatibilityError(f"tag {tag!r} does not match source v{source_version}")
    records = {record["version"]: record for record in policy["releases"]}
    record = records.get(source_version)
    if record is None:
        raise CompatibilityError(f"source version {source_version} is absent from policy")
    source_minimum = _source_minimum(ROOT / "Package.swift")
    if record["min_macos"] != source_minimum:
        raise CompatibilityError(
            f"v{source_version} policy minimum {record['min_macos']} differs from Package.swift {source_minimum}"
        )
    if bundle is not None:
        plist_path = bundle / "Contents/Info.plist"
        executable = bundle / "Contents/MacOS/AerialDrop"
        try:
            with plist_path.open("rb") as handle:
                info = plistlib.load(handle)
        except (OSError, ValueError, TypeError) as error:
            raise CompatibilityError(f"cannot read bundle Info.plist: {error}") from error
        if info.get("CFBundleShortVersionString") != source_version:
            raise CompatibilityError("bundle version differs from source version")
        bundle_minimum = info.get("LSMinimumSystemVersion")
        if bundle_minimum != f"{source_minimum}.0":
            raise CompatibilityError("bundle macOS minimum differs from source and policy")
        try:
            output = subprocess.check_output(["lipo", "-archs", str(executable)], text=True)
        except (OSError, subprocess.CalledProcessError) as error:
            raise CompatibilityError(f"cannot inspect bundle binary architectures: {error}") from error
        actual = set(output.split())
        if not actual or actual != set(record["architectures"]):
            raise CompatibilityError(
                f"bundle architectures {sorted(actual)} differ from policy {record['architectures']}"
            )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    validate = subparsers.add_parser("validate", help="validate policy and current release source/bundle")
    validate.add_argument("--policy", type=Path, default=DEFAULT_POLICY)
    validate.add_argument("--tag", help="expected v-prefixed source/release tag")
    validate.add_argument("--bundle", type=Path, help="built AerialDrop.app bundle")
    resolve = subparsers.add_parser("resolve", help="resolve a GitHub releases API catalogue")
    resolve.add_argument("--policy", type=Path, default=DEFAULT_POLICY)
    resolve.add_argument("--releases", type=Path, required=True)
    resolve.add_argument("--macos", type=int, required=True, help="macOS major version")
    resolve.add_argument("--arch", required=True)
    resolve.add_argument("--version", help="optional exact version without v prefix")
    arguments = parser.parse_args(argv)
    try:
        policy = json.loads(arguments.policy.read_text(encoding="utf-8"))
        if arguments.command == "validate":
            validate_source(policy, tag=arguments.tag, bundle=arguments.bundle)
            print("compatibility policy and source are valid")
        else:
            catalogue = json.loads(arguments.releases.read_text(encoding="utf-8"))
            selected = resolve_release(
                policy, catalogue, arguments.macos, arguments.arch, arguments.version
            )
            print(json.dumps(selected, sort_keys=True))
    except (OSError, json.JSONDecodeError, CompatibilityError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
