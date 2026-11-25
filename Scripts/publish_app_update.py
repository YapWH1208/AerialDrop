#!/usr/bin/env python3
"""Prepare and publish AerialDrop's signed stable GitHub releases."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET
from collections.abc import Iterable
from pathlib import Path

from release_compatibility import BASE_URL, DEFAULT_POLICY, DIGEST_RE, validate_policy, version_key
from sparkle_appcast import (
    KEY_ENV,
    FileDigest,
    Release,
    asset_name,
    decoded_key,
    generate_appcast,
    local_digest,
    parse_history,
    read_bundle,
    run_with_key,
    split_signed_feed,
)

REPOSITORY = "YapWH1208/AerialDrop"
RELEASES_API = f"repos/{REPOSITORY}/releases"
APPCAST = "appcast.xml"
NOTES = "release-notes.md"
PREDECESSOR = "predecessor.json"
LEGACY_TAG = "v1.1.10"
RETRY = "Rerun the failed publication job with the original signed workflow artifact."
PUBLIC_KEY_ENV = "AERIALDROP_UPDATE_PUBLIC_KEY"
DRAFT_VISIBILITY_DELAYS = (1, 2, 4, 8)
VERIFY_SIGNATURE = """
import CryptoKit
import Foundation

guard let publicKey = Data(base64Encoded: readLine() ?? ""),
      let signature = Data(base64Encoded: CommandLine.arguments[2]) else {
    exit(EXIT_FAILURE)
}
let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
let payload = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]), options: .mappedIfSafe)
if !key.isValidSignature(signature, for: payload) {
    exit(EXIT_FAILURE)
}
"""


class PublishError(ValueError):
    pass


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


def download_asset(tag: str, name: str, directory: Path) -> Path:
    gh_release("download", tag, "--pattern", name, "--dir", str(directory))
    return directory / name


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


def remote_digest(tag: str, name: str, asset: dict, *, draft: bool = False) -> FileDigest:
    digest = asset.get("digest")
    size = asset.get("size")
    match = DIGEST_RE.fullmatch(digest) if isinstance(digest, str) else None
    if (match is None or type(size) is not int or size <= 0 or asset.get("state") != "uploaded"
            or (not draft and asset.get("browser_download_url") != f"{BASE_URL}/{tag}/{name}")):
        raise PublishError(f"{tag} has invalid GitHub asset metadata for {name}")
    return FileDigest(size, match[1].lower())


def asset_slots(tag: str) -> tuple[str, str]:
    return asset_name(version_for(tag)), APPCAST


def published_digests(tag: str, release: dict | None) -> dict[str, FileDigest] | None:
    if release is None or is_draft(release):
        return None
    if not is_published(release):
        raise PublishError(f"{tag} is neither a stable draft nor a published stable release")
    assets = release_assets(release)
    digests = {}
    for name in asset_slots(tag):
        if name not in assets:
            raise PublishError(f"published {tag} is missing {name}")
        digests[name] = remote_digest(tag, name, assets[name])
    return digests


def verify_tag_commit(tag: str, commit: str) -> None:
    ref = json.loads(gh("api", "--hostname", "github.com", f"repos/{REPOSITORY}/git/ref/tags/{tag}"))
    if not isinstance(ref, dict) or ref.get("ref") != f"refs/tags/{tag}":
        raise PublishError(f"GitHub did not return the exact tag ref for {tag}")
    target = ref.get("object")
    visited = set()
    while isinstance(target, dict):
        sha = target.get("sha")
        if not isinstance(sha, str) or re.fullmatch(r"[0-9a-f]{40}", sha) is None or sha in visited:
            break
        if target.get("type") == "commit" and sha == commit:
            return
        if target.get("type") != "tag":
            break
        visited.add(sha)
        annotated_tag = json.loads(gh("api", "--hostname", "github.com", f"repos/{REPOSITORY}/git/tags/{sha}"))
        target = annotated_tag.get("object") if isinstance(annotated_tag, dict) else None
    raise PublishError(f"{tag} no longer points to the checked-out release commit")


def latest_predecessor(tag: str) -> dict:
    release = json.loads(gh("api", "--hostname", "github.com", f"{RELEASES_API}/latest"))
    if not isinstance(release, dict) or not is_published(release):
        raise PublishError("GitHub's latest release must be a published stable release")
    previous = release.get("tag_name")
    if version_key(version_for(previous)) >= version_key(version_for(tag)):
        raise PublishError(f"GitHub's latest release {previous} must be older than {tag}")
    release_id(release)
    return release


def predecessor_snapshot(release: dict) -> dict:
    tag = release["tag_name"]
    archive, feed = asset_slots(tag)
    assets = release_assets(release)
    if archive not in assets:
        raise PublishError(f"latest release {tag} is missing {archive}")
    archive_digest = remote_digest(tag, archive, assets[archive])
    feed_digest = remote_digest(tag, feed, assets[feed]) if feed in assets else None
    return {
        "tag": tag,
        "id": release_id(release),
        "archive_size": archive_digest.size,
        "archive_sha256": archive_digest.sha256,
        "feed_sha256": feed_digest.sha256 if feed_digest is not None else None,
    }


def published_archives(catalogue: dict[str, dict], versions: Iterable[str]) -> dict[str, FileDigest]:
    archives = {}
    for version in versions:
        tag = f"v{version}"
        release = catalogue.get(tag)
        if release is None or not is_published(release):
            continue
        name = asset_name(version)
        try:
            archives[version] = remote_digest(tag, name, release_assets(release)[name])
        except (PublishError, KeyError):
            # Incomplete historical releases have no downloadable enclosure to retain.
            continue
    return archives


def verify_feed_head(data: bytes, version: str, digest: FileDigest, *,
                     allow_legacy: bool = False) -> list[Release]:
    releases = parse_history(data)
    current = releases[0]
    if (current.version != version or current.size != digest.size
            or (current.sha256 != digest.sha256 and not (allow_legacy and current.sha256 is None))):
        raise PublishError(f"{APPCAST} must start with v{version} and identify its ZIP")
    return releases


def verify_history(history: list[Release], catalogue: dict[str, dict]) -> None:
    archives = published_archives(catalogue, (release.version for release in history))
    for release in history:
        if release.sha256 is None or archives.get(release.version) != FileDigest(release.size, release.sha256):
            raise PublishError(f"retained ZIP for v{release.version} changed or is unavailable. Prepare the release again.")


def verify_public_release(tag: str, digests: dict[str, FileDigest], key: str) -> None:
    pinned_key = decoded_key(key, 32, PUBLIC_KEY_ENV)
    archive_name, feed_name = asset_slots(tag)
    with tempfile.TemporaryDirectory(prefix="aerialdrop-public-release-") as directory:
        work = Path(directory).resolve()

        def verified_download(name: str) -> Path:
            path = download_asset(tag, name, work)
            if local_digest(path) != digests[name]:
                raise PublishError(f"downloaded {name} does not match {tag} asset metadata")
            return path

        def verify_signature(path: Path, signature: str, label: str) -> None:
            run_with_key(
                ["swift", "-module-cache-path", str(work / "module-cache"), "-e", VERIFY_SIGNATURE,
                 str(path), signature], key, work, f"published {label} signature verification",
            )

        data = verified_download(feed_name).read_bytes()
        payload, signature = split_signed_feed(data)
        payload_path = work / "appcast-payload"
        payload_path.write_bytes(payload)
        verify_signature(payload_path, signature, "appcast")
        head = verify_feed_head(data, version_for(tag), digests[archive_name], allow_legacy=True)[0]

        archive = verified_download(archive_name)
        verify_signature(archive, head.signature, "ZIP")
        build, embedded_key = read_bundle(archive, head.version, head.minimum)
        if build != head.build or embedded_key != pinned_key:
            raise PublishError(f"published {tag} ZIP build or update key does not match the trusted appcast")


def release_status(tag: str, commit: str, public_key: str) -> bool:
    release = release_catalogue().get(tag)
    digests = published_digests(tag, release)
    if digests is None:
        return False
    identifier = release_id(release)
    verify_public_release(tag, digests, public_key)
    verify_tag_commit(tag, commit)
    current = release_catalogue().get(tag)
    if published_digests(tag, current) != digests or release_id(current) != identifier:
        raise PublishError(f"published {tag} changed during signature verification")
    return True


def prepare(tag: str, archive: Path, notes: Path, sign_tool: Path, output: Path) -> None:
    predecessor = latest_predecessor(tag)
    previous_tag = predecessor["tag_name"]
    snapshot = predecessor_snapshot(predecessor)
    catalogue = release_catalogue()
    listed = catalogue.get(previous_tag)
    if listed is None or not is_published(listed) or predecessor_snapshot(listed) != snapshot:
        raise PublishError(f"{previous_tag} changed while fetching published release metadata")
    policy = validate_policy(json.loads(DEFAULT_POLICY.read_text(encoding="utf-8")))
    archives = published_archives(catalogue, (record["version"] for record in policy["releases"]))
    previous_digest = FileDigest(snapshot["archive_size"], snapshot["archive_sha256"])
    assets = release_assets(predecessor)
    with tempfile.TemporaryDirectory(prefix="aerialdrop-release-") as directory:
        previous_feed = None
        if APPCAST in assets:
            expected = remote_digest(previous_tag, APPCAST, assets[APPCAST])
            previous_feed = download_asset(previous_tag, APPCAST, Path(directory))
            if local_digest(previous_feed) != expected:
                raise PublishError(f"downloaded {APPCAST} does not match {previous_tag} asset metadata")
        elif previous_tag != LEGACY_TAG:
            raise PublishError(f"latest release {previous_tag} is missing its signed {APPCAST}")
        def load_historical_archive(version: str, work: Path) -> Path:
            return download_asset(f"v{version}", asset_name(version), work)

        generate_appcast(
            tag=tag, archive=archive, output=output, sign_tool=sign_tool, policy=policy,
            key=os.environ.get(KEY_ENV, ""), notes=notes.read_text(encoding="utf-8"),
            previous_feed=previous_feed, published_archives=archives,
            expected_predecessor=(version_for(previous_tag), previous_digest) if previous_feed else None,
            load_historical_archive=load_historical_archive,
        )
    output.with_name(PREDECESSOR).write_text(json.dumps(snapshot) + "\n", encoding="utf-8")


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
            if remote_digest(tag, name, asset, draft=True) != expected[name]:
                raise PublishError(f"draft {tag} has different bytes for {name}")
    except PublishError as error:
        raise PublishError(f"{error}. {RETRY}") from error
    return [name for name in expected if name not in assets]


def current_draft(catalogue: dict[str, dict], tag: str, identifier: int | None = None) -> dict:
    release = catalogue.get(tag)
    if release is None or not is_draft(release):
        raise PublishError(f"expected GitHub to report a stable draft for {tag}")
    if identifier is not None and release_id(release) != identifier:
        raise PublishError(f"draft {tag} changed its GitHub release ID. {RETRY}")
    return release


def wait_for_new_draft(tag: str) -> dict:
    """Wait briefly for a newly created draft to appear in the release catalogue."""
    for delay in (*DRAFT_VISIBILITY_DELAYS, None):
        catalogue = release_catalogue()
        if tag in catalogue:
            draft = current_draft(catalogue, tag)
            release_id(draft)
            return draft
        if delay is not None:
            time.sleep(delay)
    raise PublishError(f"expected GitHub to report a stable draft for {tag}. {RETRY}")


def publish(tag: str, directory: Path, commit: str) -> None:
    archive, feed = asset_slots(tag)
    expected = {name: local_digest(directory / name) for name in (archive, feed)}
    catalogue = release_catalogue()
    release = catalogue.get(tag)
    published = published_digests(tag, release)
    verify_tag_commit(tag, commit)
    if published is not None:
        if published != expected:
            raise PublishError(f"published {tag} does not match the prepared release assets")
        return

    notes_path = directory / NOTES
    if notes_path.is_symlink() or not notes_path.is_file():
        raise PublishError(f"expected a regular file at {notes_path}")
    notes = notes_path.read_text(encoding="utf-8")
    if not notes.strip():
        raise PublishError(f"expected nonempty release notes at {notes_path}")
    history = verify_feed_head((directory / feed).read_bytes(), version_for(tag), expected[archive])[1:]
    verify_history(history, catalogue)
    snapshot = json.loads((directory / PREDECESSOR).read_text(encoding="utf-8"))
    if predecessor_snapshot(latest_predecessor(tag)) != snapshot:
        raise PublishError("GitHub's latest release changed since signing. Prepare the release again.")
    if release is None:
        gh_release("create", tag, "--verify-tag", "--draft", "--title", tag,
                   "--notes-file", str(notes_path), "--target", commit)
        release = wait_for_new_draft(tag)
    identifier = release_id(release)
    missing = missing_draft_assets(tag, release, notes, expected)
    if missing:
        gh_release("upload", tag, *(str(directory / name) for name in missing))
    if predecessor_snapshot(latest_predecessor(tag)) != snapshot:
        raise PublishError("GitHub's latest release changed during staging. Prepare the release again.")
    catalogue = release_catalogue()
    draft = current_draft(catalogue, tag, identifier)
    if missing_draft_assets(tag, draft, notes, expected):
        raise PublishError(f"draft {tag} is still missing prepared release assets. {RETRY}")
    verify_history(history, catalogue)
    verify_tag_commit(tag, commit)
    gh("api", "--hostname", "github.com", "--method", "PATCH", f"{RELEASES_API}/{identifier}",
       "-F", "draft=false", "-f", "make_latest=true", "-f", f"tag_name={tag}",
       "-f", f"target_commitish={commit}")
    published = release_catalogue().get(tag)
    actual = published_digests(tag, published)
    if actual is None or release_id(published) != identifier:
        raise PublishError(f"GitHub did not confirm publication of {tag}")
    if actual != expected:
        raise PublishError(f"published {tag} does not match the prepared release assets")
    verify_tag_commit(tag, commit)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    status = commands.add_parser("status", help="report whether the stable release is already public")
    signing = commands.add_parser("prepare", help="prepare the signed feed from GitHub release history")
    publication = commands.add_parser("publish", help="stage, verify, and publish signed release assets")
    for command in (status, signing, publication):
        command.add_argument("--tag", required=True)
    for command in (status, publication):
        command.add_argument("--commit", required=True, help="the checked-out commit for the release tag")
    for option in ("--archive", "--notes", "--sign-tool", "--output"):
        signing.add_argument(option, required=True, type=Path)
    publication.add_argument("--assets-dir", required=True, type=Path)
    arguments = parser.parse_args()
    try:
        version_for(arguments.tag)
        if arguments.command == "status":
            published = release_status(arguments.tag, arguments.commit, os.environ.get(PUBLIC_KEY_ENV, ""))
            print(f"published={str(published).lower()}")
        elif arguments.command == "prepare":
            prepare(arguments.tag, arguments.archive, arguments.notes, arguments.sign_tool, arguments.output)
        else:
            publish(arguments.tag, arguments.assets_dir, arguments.commit)
    except (OSError, ValueError, ET.ParseError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
