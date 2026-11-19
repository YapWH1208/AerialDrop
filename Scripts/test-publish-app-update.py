#!/usr/bin/env python3
"""Offline tests for AerialDrop's GitHub update publisher."""

import base64
import copy
import hashlib
import json
import os
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from unittest.mock import patch

import publish_app_update as publisher
import sparkle_appcast as appcast

TAG = "v1.2.1"
PREVIOUS = "v1.2.0"
ZIP = appcast.asset_name(TAG[1:])
ZIP_BYTES = b"official archive"
NOTES = "## Updates\n\n- Add signed updates.\n"
SIGNATURE = base64.b64encode(bytes(64)).decode("ascii")


def feed(tag, archive=ZIP_BYTES):
    root = ET.Element("rss", version="2.0")
    channel = ET.SubElement(root, "channel")
    version = tag[1:]
    release = appcast.Release(version, 42, len(archive), SIGNATURE, None, 26,
                             frozenset(("arm64", "x86_64")))
    appcast.write_item(channel, release, {"min_macos": 26, "max_macos": None,
                                          "architectures": ["arm64", "x86_64"]})
    payload = ET.tostring(root) + b"\n"
    return payload + (f"<!-- sparkle-signatures:\nedSignature: {SIGNATURE}\n"
                      f"length: {len(payload)}\n-->\n").encode("ascii")


def asset(tag, name, payload):
    return {"name": name, "size": len(payload), "state": "uploaded",
            "digest": f"sha256:{hashlib.sha256(payload).hexdigest()}",
            "browser_download_url": f"{publisher.BASE_URL}/{tag}/{name}"}


def release(tag, identifier, *, draft=False, include_feed=True):
    return {"tag_name": tag, "id": identifier, "draft": draft, "prerelease": False,
            "published_at": None if draft else "2026-11-19T01:00:00Z",
            "body": NOTES, "assets": [asset(tag, appcast.asset_name(tag[1:]), ZIP_BYTES),
                                      *([asset(tag, publisher.APPCAST, feed(tag))] if include_feed else [])]}


class FakeGitHub:
    def __init__(self, previous=PREVIOUS, include_feed=True):
        self.latest = previous
        self.releases = {previous: release(previous, 1, include_feed=include_feed)}
        self.calls = []
        self.bad_download = False
        self.download_count = 0
        self.change_draft_id_on_upload = False
        self.corrupt_asset_on_upload = False

    def __call__(self, *args):
        if args[0] == "api":
            if args == ("api", "--hostname", "github.com", f"{publisher.RELEASES_API}/latest"):
                return json.dumps(self.releases[self.latest])
            assert args == ("api", "--hostname", "github.com", "--paginate", "--slurp",
                            f"{publisher.RELEASES_API}?per_page=100"), args
            releases = copy.deepcopy(list(self.releases.values()))
            for entry in releases:
                for item in entry["assets"]:
                    item["download_count"] = self.download_count
            return json.dumps([releases[:1], releases[1:]])
        assert args[0] == "release" and args[3:5] == ("--repo", "github.com/YapWH1208/AerialDrop"), args
        command, tag = args[1:3]
        options = args[5:]
        self.calls.append((command, tag, options))
        if command == "download":
            assert options[:3] == ("--pattern", publisher.APPCAST, "--dir"), args
            payload = b"wrong bytes" if self.bad_download else feed(tag)
            (Path(options[3]) / publisher.APPCAST).write_bytes(payload)
        elif command == "create":
            assert tag not in self.releases and options[:5] == (
                "--verify-tag", "--draft", "--title", tag, "--notes-file",
            ), args
            self.releases[tag] = {**release(tag, 2, draft=True), "assets": [],
                                  "body": Path(options[5]).read_text(encoding="utf-8")}
        elif command == "upload":
            draft = self.releases[tag]
            assert draft["draft"] is True, args
            for path in map(Path, options):
                assert path.name not in {item["name"] for item in draft["assets"]}, args
                draft["assets"].append(asset(tag, path.name, path.read_bytes()))
            if self.change_draft_id_on_upload:
                draft["id"] += 1
            if self.corrupt_asset_on_upload:
                draft["assets"][-1]["digest"] = f"sha256:{'0' * 64}"
        elif command == "edit":
            assert options == ("--verify-tag", "--draft=false", "--latest"), args
            assert {item["name"] for item in self.releases[tag]["assets"]} == {ZIP, publisher.APPCAST}
            self.releases[tag].update(draft=False, published_at="2026-11-19T02:00:00Z")
            self.latest = tag
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
            self.assertEqual(kwargs["published_archives"], {PREVIOUS[1:]: len(ZIP_BYTES)})
            self.assertEqual(kwargs["expected_predecessor"], (PREVIOUS[1:], len(ZIP_BYTES)))
            self.assertEqual(kwargs["notes"], NOTES)

        self.prepare(github, generate)
        self.assertEqual(len(generated), 1)
        self.assertEqual([(command, tag) for command, tag, _ in github.calls], [("download", PREVIOUS)])

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

    def test_publish_stages_then_edits_and_public_rerun_is_a_noop(self):
        github = FakeGitHub()
        with patch.object(publisher, "gh", github):
            publisher.publish(TAG, self.directory)
            publisher.publish(TAG, self.directory / "not-present")
        self.assertEqual([command for command, _, _ in github.calls], ["create", "upload", "edit"])
        self.assertEqual([Path(path).name for path in github.calls[1][2]], [ZIP, publisher.APPCAST])

    def test_resume_uploads_only_missing_asset(self):
        github = FakeGitHub()
        github.releases[TAG] = release(TAG, 2, draft=True, include_feed=False)
        with patch.object(publisher, "gh", github):
            publisher.publish(TAG, self.directory)
        self.assertEqual([command for command, _, _ in github.calls], ["upload", "edit"])
        self.assertEqual(github.calls[0][2], (str(self.feed),))

    def test_rejects_invalid_draft_before_mutation_and_checks_identity_after_upload(self):
        github = FakeGitHub()
        draft = release(TAG, 2, draft=True, include_feed=False)
        github.releases[TAG] = copy.deepcopy(draft)
        github.releases[TAG]["assets"][0] = asset(TAG, ZIP, b"different archive")
        with patch.object(publisher, "gh", github):
            with self.assertRaisesRegex(publisher.PublishError, "original signed workflow artifact"):
                publisher.publish(TAG, self.directory)
            self.assertEqual(github.calls, [])
            github.releases[TAG] = draft
            github.change_draft_id_on_upload = True
            with self.assertRaisesRegex(publisher.PublishError, "changed its GitHub release ID"):
                publisher.publish(TAG, self.directory)
        self.assertEqual([command for command, _, _ in github.calls], ["upload"])

    def test_publish_revalidates_uploaded_digest_before_publication(self):
        github = FakeGitHub()
        github.corrupt_asset_on_upload = True
        with patch.object(publisher, "gh", github):
            with self.assertRaisesRegex(publisher.PublishError, "different bytes for appcast.xml"):
                publisher.publish(TAG, self.directory)
        self.assertEqual([command for command, _, _ in github.calls], ["create", "upload"])
        self.assertTrue(github.releases[TAG]["draft"])

    def test_status_checks_both_published_slots(self):
        self.assertFalse(publisher.already_published(TAG, None))
        self.assertFalse(publisher.already_published(TAG, release(TAG, 2, draft=True)))
        self.assertTrue(publisher.already_published(TAG, release(TAG, 2)))
        with self.assertRaisesRegex(publisher.PublishError, "missing appcast.xml"):
            publisher.already_published(TAG, release(TAG, 2, include_feed=False))
        metadata = release(TAG, 2)
        metadata["assets"][1]["browser_download_url"] += "?other"
        with self.assertRaisesRegex(publisher.PublishError, "invalid GitHub asset metadata"):
            publisher.already_published(TAG, metadata)


if __name__ == "__main__":
    unittest.main()
