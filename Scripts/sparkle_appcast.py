#!/usr/bin/env python3
"""Validate the official release ZIP and publishable history, then sign a Sparkle appcast."""

from __future__ import annotations

import argparse
import base64
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from dataclasses import dataclass
from pathlib import Path

from release_compatibility import BASE_URL, DEFAULT_POLICY, validate_policy, version_key


KEY_ENV = "AERIALDROP_UPDATE_PRIVATE_KEY"
FEED_URL = "https://github.com/YapWH1208/AerialDrop/releases/latest/download/appcast.xml"
NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
MAX_INTEGER = 2**63 - 1
INFO_PATH = "AerialDrop.app/Contents/Info.plist"
REQUIRED_SETTINGS = {
    "SUFeedURL": FEED_URL,
    "SUEnableAutomaticChecks": True,
    "SUAllowsAutomaticUpdates": False,
    "SUEnableSystemProfiling": False,
    "SUVerifyUpdateBeforeExtraction": True,
    "SURequireSignedFeed": True,
    "SUSignedFeedFailureExpirationInterval": 0,
}
SIGNING_BLOCK = re.compile(
    rb"<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/=]+)\nlength: ([1-9][0-9]{0,18})\n-->\n?\Z"
)
DERIVE_PUBLIC_KEY = """
import CryptoKit
import Foundation
let seed = Data(base64Encoded: readLine()!)!
let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
print(privateKey.publicKey.rawRepresentation.base64EncodedString())
"""
ET.register_namespace("sparkle", NS)


class AppcastError(ValueError):
    pass


@dataclass(frozen=True)
class Release:
    version: str
    build: int
    size: int
    signature: str
    notes: str | None
    minimum: int
    architectures: frozenset[str]


def sparkle(name: str) -> str:
    return f"{{{NS}}}{name}"


def asset_name(version: str) -> str:
    return f"AerialDrop-{version}-macOS.zip"


def asset_url(version: str) -> str:
    return f"{BASE_URL}/v{version}/{asset_name(version)}"


def positive_integer(value: str, label: str) -> int:
    if not isinstance(value, str) or not re.fullmatch(r"[1-9][0-9]{0,18}", value):
        raise AppcastError(f"{label} must be a positive integer")
    result = int(value)
    if result > MAX_INTEGER:
        raise AppcastError(f"{label} exceeds Sparkle's signed 64-bit limit")
    return result


def decoded_key(value: str, size: int, label: str) -> bytes:
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, TypeError) as error:
        raise AppcastError(f"{label} must be canonical base64 for {size} bytes") from error
    if len(decoded) != size or base64.b64encode(decoded).decode("ascii") != value:
        raise AppcastError(f"{label} must be canonical base64 for {size} bytes")
    return decoded


def run_with_key(command: list[str], key: str, working_directory: Path, operation: str) -> bytes:
    environment = {name: value for name, value in os.environ.items() if name not in {KEY_ENV, "GH_TOKEN"}}
    # Sparkle may echo a malformed secret. Never log either stream or a process exception.
    try:
        result = subprocess.run(
            command, cwd=working_directory, env=environment, input=(key + "\n").encode("ascii"),
            capture_output=True, check=False,
        )
    except OSError:
        raise AppcastError(f"could not launch {operation}") from None
    if result.returncode != 0:
        raise AppcastError(f"{operation} failed")
    return result.stdout


def read_bundle(archive: Path, version: str, minimum: int) -> tuple[int, bytes]:
    if archive.name != asset_name(version):
        raise AppcastError("release ZIP filename does not match the tag")
    try:
        with zipfile.ZipFile(archive) as bundle:
            plists = [item for item in bundle.infolist() if item.filename == INFO_PATH]
            if len(plists) != 1 or not 0 < plists[0].file_size <= 1024 * 1024:
                raise AppcastError("release ZIP must contain one regular-sized app Info.plist")
            info = plistlib.loads(bundle.read(plists[0]))
    except (zipfile.BadZipFile, plistlib.InvalidFileException, RuntimeError, ET.ParseError):
        raise AppcastError("could not read release ZIP app Info.plist") from None
    if not isinstance(info, dict):
        raise AppcastError("release ZIP app Info.plist must contain a dictionary")
    expected = {
        **REQUIRED_SETTINGS,
        "CFBundleIdentifier": "com.yapwh.aerialdrop",
        "CFBundleShortVersionString": version,
        "LSMinimumSystemVersion": f"{minimum}.0",
    }
    for field, value in expected.items():
        actual = info.get(field)
        if type(actual) is not type(value) or actual != value:
            raise AppcastError(f"release ZIP has missing or invalid {field}")
    if "SUPublicDSAKey" in info or "SUPublicDSAKeyFile" in info:
        raise AppcastError("release ZIP includes a legacy Sparkle signing key")
    return (
        positive_integer(info.get("CFBundleVersion"), "CFBundleVersion"),
        decoded_key(info.get("SUPublicEDKey"), 32, "SUPublicEDKey"),
    )


def parse_history(data: bytes) -> list[Release]:
    # Parse only the bytes covered by the verified signature.
    block = SIGNING_BLOCK.search(data)
    if block is None or int(block[2]) != block.start():
        raise AppcastError("previous appcast has an invalid signature block or signed length")
    decoded_key(block[1].decode("ascii"), 64, "appcast Ed25519 signature")
    root = ET.fromstring(data[:block.start()])
    channels = root.findall("channel")
    if root.tag != "rss" or root.get("version") != "2.0" or len(channels) != 1:
        raise AppcastError("previous appcast is not a Sparkle RSS feed")
    releases = []
    for item in channels[0].findall("item"):
        versions = item.findall(sparkle("shortVersionString"))
        builds = item.findall(sparkle("version"))
        enclosures = item.findall("enclosure")
        descriptions = item.findall("description")
        if len(versions) != 1 or len(builds) != 1 or len(enclosures) != 1 or len(descriptions) > 1:
            raise AppcastError("previous appcast item has missing or duplicate release metadata")
        version = versions[0].text
        version_key(version)
        build = positive_integer(builds[0].text, "previous appcast build version")
        enclosure = enclosures[0]
        if (
            enclosure.get("url") != asset_url(version)
            or enclosure.get("type") != "application/octet-stream"
            or set(enclosure.attrib) != {"url", "length", "type", sparkle("edSignature")}
        ):
            raise AppcastError("previous appcast has an unexpected enclosure")
        size = positive_integer(enclosure.get("length"), "previous appcast ZIP length")
        signature = enclosure.get(sparkle("edSignature"))
        decoded_key(signature, 64, "previous appcast ZIP Ed25519 signature")
        notes = None
        if descriptions:
            description = descriptions[0]
            if description.get(sparkle("format")) != "markdown" or len(description):
                raise AppcastError("previous appcast has unexpected inline release notes")
            notes = description.text
        minimum_elements = item.findall(sparkle("minimumSystemVersion"))
        hardware = item.findall(sparkle("hardwareRequirements"))
        if len(minimum_elements) != 1 or len(hardware) > 1:
            raise AppcastError("previous appcast has missing or duplicate compatibility fields")
        minimum = re.fullmatch(r"([0-9]{2,3})\.0", minimum_elements[0].text or "")
        if minimum is None or not 26 <= int(minimum[1]) <= 999:
            raise AppcastError("previous appcast has an invalid minimum macOS version")
        if hardware and hardware[0].text != "arm64":
            raise AppcastError("previous appcast has an unsupported hardware requirement")
        architectures = frozenset(("arm64",)) if hardware else frozenset(("arm64", "x86_64"))
        releases.append(Release(version, build, size, signature, notes, int(minimum[1]), architectures))
    if not releases:
        raise AppcastError("previous appcast contains no releases")
    return releases


def write_item(channel: ET.Element, release: Release, record: dict) -> None:
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"AerialDrop {release.version}"
    ET.SubElement(item, sparkle("version")).text = str(release.build)
    ET.SubElement(item, sparkle("shortVersionString")).text = release.version
    ET.SubElement(item, sparkle("minimumSystemVersion")).text = f"{record['min_macos']}.0"
    maximum = record["max_macos"]
    if maximum is not None:
        ET.SubElement(item, sparkle("maximumSystemVersion")).text = (
            f"{maximum}.{MAX_INTEGER}.{MAX_INTEGER}"
        )
    architectures = set(record["architectures"])
    if architectures == {"arm64"}:
        ET.SubElement(item, sparkle("hardwareRequirements")).text = "arm64"
    elif architectures != {"arm64", "x86_64"}:
        raise AppcastError(f"Sparkle cannot represent architectures for v{release.version}")
    if release.notes:
        ET.SubElement(item, "description", {sparkle("format"): "markdown"}).text = release.notes
    ET.SubElement(item, "enclosure", {
        "url": asset_url(release.version),
        "length": str(release.size),
        "type": "application/octet-stream",
        sparkle("edSignature"): release.signature,
    })


def generate_appcast(
    tag: str, archive: Path, output: Path, sign_tool: Path, policy: dict, key: str,
    notes: str | None = None, previous_feed: Path | None = None,
    published_archives: dict[str, int] | None = None,
    expected_predecessor: tuple[str, int] | None = None,
) -> None:
    decoded_key(key, 32, KEY_ENV)
    if not tag.startswith("v"):
        raise AppcastError("expected a stable v-prefixed release tag")
    version = tag[1:]
    version_key(version)
    declarations = {record["version"]: record for record in validate_policy(policy)["releases"]}
    if version not in declarations:
        raise AppcastError(f"{tag} is missing from the compatibility policy")
    archive, sign_tool = archive.resolve(), sign_tool.resolve()
    build, pinned_key = read_bundle(archive, version, declarations[version]["min_macos"])
    size = positive_integer(str(archive.stat().st_size), "release ZIP length")

    with tempfile.TemporaryDirectory(prefix=".appcast-", dir=output.parent) as directory:
        work = Path(directory).resolve()

        def sign(operation: str, *arguments: str) -> bytes:
            return run_with_key([str(sign_tool), "--ed-key-file", "-", *arguments], key, work, operation)

        derived_key = run_with_key(
            ["swift", "-module-cache-path", str(work / "module-cache"), "-e", DERIVE_PUBLIC_KEY],
            key, work, "Ed25519 public-key derivation",
        ).strip().decode("ascii", errors="replace")
        if pinned_key != decoded_key(derived_key, 32, "derived Ed25519 public key"):
            raise AppcastError("release ZIP SUPublicEDKey does not match the signing key")

        history = []
        if previous_feed is not None:
            snapshot = work / "previous.xml"
            data = previous_feed.read_bytes()
            snapshot.write_bytes(data)
            sign("previous appcast signature verification", "--verify", str(snapshot))
            history = parse_history(data)
            if expected_predecessor is not None and (history[0].version, history[0].size) != expected_predecessor:
                raise AppcastError("previous signed appcast does not match the latest published release ZIP")
            history.sort(key=lambda release: version_key(release.version))

        prior_version, prior_build = (-1, -1, -1), 0
        for historical in history:
            numeric_version = version_key(historical.version)
            if numeric_version <= prior_version or historical.build <= prior_build:
                raise AppcastError("previous appcast contains duplicate or non-increasing versions or builds")
            prior_version, prior_build = numeric_version, historical.build
        if version_key(version) <= prior_version or build <= prior_build:
            raise AppcastError("release would tie or downgrade an existing version or build")

        signature = sign("release ZIP signing", "-p", str(archive)).strip().decode("ascii", errors="replace")
        decoded_key(signature, 64, "release ZIP Ed25519 signature")
        sign("release ZIP signature verification", "--verify", str(archive), signature)

        root = ET.Element("rss", version="2.0")
        channel = ET.SubElement(root, "channel")
        ET.SubElement(channel, "title").text = "AerialDrop"
        ET.SubElement(channel, "link").text = "https://github.com/YapWH1208/AerialDrop"
        ET.SubElement(channel, "description").text = "Stable AerialDrop releases"
        current_record = declarations[version]
        current = Release(
            version, build, size, signature, notes, current_record["min_macos"],
            frozenset(current_record["architectures"]),
        )
        available_history = (
            release for release in reversed(history)
            if published_archives is None or published_archives.get(release.version) == release.size
        )
        for release in [current, *available_history]:
            record = declarations.get(release.version)
            if record is None:
                continue
            if record["min_macos"] < release.minimum or not release.architectures.issuperset(
                record["architectures"]
            ):
                raise AppcastError(f"compatibility policy widens signed history for v{release.version}")
            write_item(channel, release, record)
        ET.indent(root)
        payload = ET.tostring(root, encoding="utf-8", xml_declaration=True) + b"\n"
        ET.fromstring(payload)
        staged = work / "appcast.xml"
        staged.write_bytes(payload)
        sign("appcast signing", str(staged))
        sign("appcast signature verification", "--verify", str(staged))
        parse_history(staged.read_bytes())
        staged.replace(output)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--sign-tool", required=True, type=Path)
    parser.add_argument("--notes", type=Path)
    parser.add_argument("--previous-feed", type=Path)
    parser.add_argument("--policy", type=Path, default=DEFAULT_POLICY)
    arguments = parser.parse_args()
    try:
        generate_appcast(
            tag=arguments.tag,
            archive=arguments.archive,
            output=arguments.output,
            sign_tool=arguments.sign_tool,
            policy=json.loads(arguments.policy.read_text(encoding="utf-8")),
            key=os.environ.get(KEY_ENV, ""),
            notes=arguments.notes.read_text(encoding="utf-8") if arguments.notes else None,
            previous_feed=arguments.previous_feed,
        )
    except (OSError, ValueError, ET.ParseError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
