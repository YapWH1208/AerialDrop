#!/usr/bin/env python3
"""Prepare and publish AerialDrop's signed stable GitHub releases."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

from release_compatibility import BASE_URL, DEFAULT_POLICY, DIGEST_RE, validate_policy, version_key
from sparkle_appcast import KEY_ENV, asset_name, generate_appcast, parse_history

REPOSITORY = "YapWH1208/AerialDrop"
RELEASES_API = f"repos/{REPOSITORY}/releases"
APPCAST = "appcast.xml"
NOTES = "release-notes.md"
LEGACY_TAG = "v1.1.10"
RETRY = "Rerun the failed publication job with the original signed workflow artifact."


class PublishError(ValueError):
    pass


@dataclass(frozen=True)
class FileDigest:
    size: int
    sha256: str


def gh(*arguments: str) -> str:
    environment = {key: value for key, value in os.environ.items() if key != KEY_ENV}
    result = subprocess.run(
        ["gh", *arguments], env=environment, capture_output=True, text=True, check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.strip()
        raise PublishError(f"gh {' '.join(arguments[:2])} failed: {detail}")
    return result.stdout


def gh_release(command: str, tag: str, *arguments: str) -> str:
    return gh("release", command, tag, "--repo", f"github.com/{REPOSITORY}", *arguments)


def version_for(tag: str) -> str:
    if not isinstance(tag, str) or not tag.startswith("v"):
        raise PublishError(f"expected a stable v-prefixed release tag, got {tag!r}")
    version = tag[1:]
    version_key(version)
    return version


def release_catalogue() -> dict[str, dict]:
    pages = json.loads(gh("api", "--hostname", "github.com", "--paginate", "--slurp",
                          f"{RELEASES_API}?per_page=100"))
    if not isinstance(pages, list) or not pages or any(not isinstance(page, list) for page in pages):
        raise PublishError("invalid GitHub release catalogue")
    releases = {}
    for page in pages:
        for release in page:
            tag = release.get("tag_name") if isinstance(release, dict) else None
            if not isinstance(tag, str) or not tag or tag in releases:
                raise PublishError("missing or duplicate GitHub release tag")
            releases[tag] = release
    return releases


def is_published(release: dict) -> bool:
    published_at = release.get("published_at")
    return (release.get("draft") is False and release.get("prerelease") is False
            and isinstance(published_at, str) and bool(published_at))


def is_draft(release: dict) -> bool:
    return (release.get("draft") is True and release.get("prerelease") is False
            and "published_at" in release and release["published_at"] is None)


def release_id(release: dict) -> int:
    identifier = release.get("id")
    if type(identifier) is not int or identifier <= 0:
        raise PublishError(f"{release.get('tag_name')!r} has an invalid GitHub release ID")
    return identifier


def release_assets(release: dict) -> dict[str, dict]:
    assets = release.get("assets")
    if not isinstance(assets, list):
        raise PublishError(f"{release['tag_name']} has invalid release assets")
    indexed = {}
    for asset in assets:
        name = asset.get("name") if isinstance(asset, dict) else None
        if not isinstance(name, str) or not name or name in indexed:
            raise PublishError(f"{release['tag_name']} has a missing or duplicate asset name")
        indexed[name] = asset
    return indexed


def remote_digest(tag: str, name: str, asset: dict) -> FileDigest:
    digest = asset.get("digest")
    size = asset.get("size")
    match = DIGEST_RE.fullmatch(digest) if isinstance(digest, str) else None
    if (match is None or type(size) is not int or size <= 0 or asset.get("state") != "uploaded"
            or asset.get("browser_download_url") != f"{BASE_URL}/{tag}/{name}"):
        raise PublishError(f"{tag} has invalid GitHub asset metadata for {name}")
    return FileDigest(size, match[1].lower())


def local_digest(path: Path) -> FileDigest:
    if path.is_symlink() or not path.is_file():
        raise PublishError(f"expected a nonempty regular file at {path}")
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
            size += len(chunk)
    if size == 0:
        raise PublishError(f"expected a nonempty regular file at {path}")
    return FileDigest(size, digest.hexdigest())


def asset_slots(tag: str) -> tuple[str, str]:
    return asset_name(version_for(tag)), APPCAST


def already_published(tag: str, release: dict | None) -> bool:
    if release is None or is_draft(release):
        return False
    if not is_published(release):
        raise PublishError(f"{tag} is neither a stable draft nor a published stable release")
    assets = release_assets(release)
    for name in asset_slots(tag):
        if name not in assets:
            raise PublishError(f"published {tag} is missing {name}")
        remote_digest(tag, name, assets[name])
    return True


def latest_predecessor(tag: str) -> dict:
    release = json.loads(gh("api", "--hostname", "github.com", f"{RELEASES_API}/latest"))
    if not isinstance(release, dict) or not is_published(release):
        raise PublishError("GitHub's latest release must be a published stable release")
    previous = release.get("tag_name")
    if version_key(version_for(previous)) >= version_key(version_for(tag)):
        raise PublishError(f"GitHub's latest release {previous} must be older than {tag}")
    release_id(release)
    return release


def published_archives(catalogue: dict[str, dict], policy: dict) -> dict[str, int]:
    archives = {}
    for record in policy["releases"]:
        version = record["version"]
        tag = f"v{version}"
        release = catalogue.get(tag)
        if release is None or not is_published(release):
            continue
        name = asset_name(version)
        try:
            archives[version] = remote_digest(tag, name, release_assets(release)[name]).size
        except (PublishError, KeyError):
            # Incomplete historical releases have no downloadable enclosure to retain.
            continue
    return archives


def verify_feed_head(path: Path, version: str, archive_size: int) -> None:
    release = parse_history(path.read_bytes())[0]
    if release.version != version or release.size != archive_size:
        raise PublishError(f"{path.name} must start with v{version} and its published ZIP length")


def prepare(tag: str, archive: Path, notes: Path, sign_tool: Path, output: Path) -> None:
    predecessor = latest_predecessor(tag)
    previous_tag = predecessor["tag_name"]
    catalogue = release_catalogue()
    listed = catalogue.get(previous_tag)
    if listed is None or not is_published(listed) or release_id(listed) != release_id(predecessor):
        raise PublishError(f"{previous_tag} changed while fetching published release metadata")
    policy = validate_policy(json.loads(DEFAULT_POLICY.read_text(encoding="utf-8")))
    archives = published_archives(catalogue, policy)
    previous_version = version_for(previous_tag)
    archive_slot = asset_name(previous_version)
    assets = release_assets(predecessor)
    if archive_slot not in assets:
        raise PublishError(f"latest release {previous_tag} is missing {archive_slot}")
    predecessor_archive = remote_digest(previous_tag, archive_slot, assets[archive_slot])
    listed_assets = release_assets(listed)
    for name in (archive_slot, APPCAST):
        if (name in assets) != (name in listed_assets) or (
            name in assets
            and remote_digest(previous_tag, name, assets[name]) != remote_digest(previous_tag, name, listed_assets[name])
        ):
            raise PublishError(f"{previous_tag} changed while fetching published release metadata")
    with tempfile.TemporaryDirectory(prefix="aerialdrop-release-") as directory:
        previous_feed = None
        if APPCAST in assets:
            expected = remote_digest(previous_tag, APPCAST, assets[APPCAST])
            gh_release("download", previous_tag, "--pattern", APPCAST, "--dir", directory)
            previous_feed = Path(directory) / APPCAST
            if local_digest(previous_feed) != expected:
                raise PublishError(f"downloaded {APPCAST} does not match {previous_tag} asset metadata")
        elif previous_tag != LEGACY_TAG:
            raise PublishError(f"latest release {previous_tag} is missing its signed {APPCAST}")
        generate_appcast(
            tag=tag, archive=archive, output=output, sign_tool=sign_tool, policy=policy,
            key=os.environ.get(KEY_ENV, ""), notes=notes.read_text(encoding="utf-8"),
            previous_feed=previous_feed, published_archives=archives,
            expected_predecessor=(previous_version, predecessor_archive.size) if previous_feed else None,
        )


def missing_draft_assets(tag: str, release: dict, notes: str,
                         expected: dict[str, FileDigest]) -> list[str]:
    if not is_draft(release):
        raise PublishError(f"{tag} must remain a stable draft during upload")
    if release.get("body") != notes:
        raise PublishError(f"draft {tag} has different release notes. {RETRY}")
    try:
        assets = release_assets(release)
        if assets.keys() - expected.keys():
            raise PublishError(f"draft {tag} contains unexpected assets")
        for name, asset in assets.items():
            if remote_digest(tag, name, asset) != expected[name]:
                raise PublishError(f"draft {tag} has different bytes for {name}")
    except PublishError as error:
        raise PublishError(f"{error}. {RETRY}") from error
    return [name for name in expected if name not in assets]


def current_draft(tag: str, identifier: int | None = None) -> dict:
    release = release_catalogue().get(tag)
    if release is None or not is_draft(release):
        raise PublishError(f"expected GitHub to report a stable draft for {tag}")
    if identifier is not None and release_id(release) != identifier:
        raise PublishError(f"draft {tag} changed its GitHub release ID. {RETRY}")
    return release


def publish(tag: str, directory: Path) -> None:
    release = release_catalogue().get(tag)
    if already_published(tag, release):
        return
    archive, feed = asset_slots(tag)
    expected = {name: local_digest(directory / name) for name in (archive, feed)}
    notes_path = directory / NOTES
    if notes_path.is_symlink() or not notes_path.is_file():
        raise PublishError(f"expected a regular file at {notes_path}")
    notes = notes_path.read_text(encoding="utf-8")
    if not notes.strip():
        raise PublishError(f"expected nonempty release notes at {notes_path}")
    verify_feed_head(directory / feed, version_for(tag), expected[archive].size)
    predecessor = latest_predecessor(tag)
    if release is None:
        gh_release("create", tag, "--verify-tag", "--draft", "--title", tag,
                   "--notes-file", str(notes_path))
        release = current_draft(tag)
    identifier = release_id(release)
    missing = missing_draft_assets(tag, release, notes, expected)
    if missing:
        gh_release("upload", tag, *(str(directory / name) for name in missing))
    if release_id(latest_predecessor(tag)) != release_id(predecessor):
        raise PublishError(f"GitHub's latest release changed during staging. {RETRY}")
    draft = current_draft(tag, identifier)
    if missing_draft_assets(tag, draft, notes, expected):
        raise PublishError(f"draft {tag} is still missing prepared release assets. {RETRY}")
    gh_release("edit", tag, "--verify-tag", "--draft=false", "--latest")
    published = release_catalogue().get(tag)
    if not already_published(tag, published) or release_id(published) != identifier:
        raise PublishError(f"GitHub did not confirm publication of {tag}")
    assets = release_assets(published)
    if any(remote_digest(tag, name, assets[name]) != digest for name, digest in expected.items()):
        raise PublishError(f"published {tag} does not match the prepared release assets")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    status = commands.add_parser("status", help="report whether the stable release is already public")
    signing = commands.add_parser("prepare", help="prepare the signed feed from GitHub release history")
    publication = commands.add_parser("publish", help="stage, verify, and publish signed release assets")
    for command in (status, signing, publication):
        command.add_argument("--tag", required=True)
    for option in ("--archive", "--notes", "--sign-tool", "--output"):
        signing.add_argument(option, required=True, type=Path)
    publication.add_argument("--assets-dir", required=True, type=Path)
    arguments = parser.parse_args()
    try:
        version_for(arguments.tag)
        if arguments.command == "status":
            published = already_published(arguments.tag, release_catalogue().get(arguments.tag))
            print(f"published={str(published).lower()}")
        elif arguments.command == "prepare":
            prepare(arguments.tag, arguments.archive, arguments.notes, arguments.sign_tool, arguments.output)
        else:
            publish(arguments.tag, arguments.assets_dir)
    except (OSError, ValueError, ET.ParseError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
