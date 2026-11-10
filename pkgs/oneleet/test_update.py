"""Tests for update.py (oneleet-update). Run: python3 -m unittest -v test_update"""

import contextlib
import http.client
import io
import json
import os
import tempfile
import unittest
from unittest import mock

import update

FEED = """version: 2.5.0
files:
  - url: Oneleet_2.5.0_x86_64.rpm
    sha512: V88fCw4AEVYs6O+5uY1DWdFa9uNI3C2ENgpSjMXqXtInv09RY3pVSkF0AETSA5R6tPjOKSanQbNqN9tyUZ+2Aw==
    size: 114725911
  - url: Oneleet_2.5.0_amd64.deb
    sha512: 0+cSZfVZ9U2JbFzZtKQzjHOgwCEhRws7VtDCrLBSPjk5/lwQDTe8d6SzLBSRVixdMGO6BWrlL5QBXbJ+aNnw6Q==
    size: 131902548
path: Oneleet_2.5.0_x86_64.rpm
sha512: V88fCw4AEVYs6O+5uY1DWdFa9uNI3C2ENgpSjMXqXtInv09RY3pVSkF0AETSA5R6tPjOKSanQbNqN9tyUZ+2Aw==
releaseDate: '2026-10-29T22:28:56.063Z'
"""
DEB_SHA = "0+cSZfVZ9U2JbFzZtKQzjHOgwCEhRws7VtDCrLBSPjk5/lwQDTe8d6SzLBSRVixdMGO6BWrlL5QBXbJ+aNnw6Q=="
OLD_PIN = {"version": "2.0.0-beta.18", "hash": "sha512-old"}


def feed_with_version(version):
    return FEED.replace("version: 2.5.0", f"version: {version}", 1)


class VersionTests(unittest.TestCase):
    def test_semver_order(self):
        versions = ["2.6.0", "2.0.0-beta.18", "2.6.0-beta.3", "2.5.0", "2.3.1"]
        self.assertEqual(
            sorted(versions, key=update.semver_key),
            ["2.0.0-beta.18", "2.3.1", "2.5.0", "2.6.0-beta.3", "2.6.0"],
        )

    def test_is_newer(self):
        self.assertTrue(update.is_newer("2.6.0", "2.6.0-beta.3"))
        self.assertTrue(update.is_newer("2.0.0-beta.10", "2.0.0-beta.9"))
        self.assertFalse(update.is_newer("2.5.0", "2.5.0"))
        self.assertFalse(update.is_newer("2.3.1", "2.5.0"))

    def test_semver_rejects(self):
        for bad in ["latest", "2.5", "2.6.0+build.1"]:
            with self.subTest(bad=bad):
                with self.assertRaises(ValueError):
                    update.semver_key(bad)


class FeedTests(unittest.TestCase):
    def test_parse_feed(self):
        self.assertEqual(
            update.parse_feed(FEED),
            update.FeedEntry("2.5.0", "Oneleet_2.5.0_amd64.deb", DEB_SHA),
        )

    def test_parse_feed_errors(self):
        no_deb = "\n".join(
            line
            for line in FEED.splitlines()
            if "amd64.deb" not in line
            and DEB_SHA not in line
            and "size: 131902548" not in line
        )
        no_version = FEED.replace("version: 2.5.0\n", "", 1)
        for text in ["<html>nope</html>", no_deb, no_version]:
            with self.subTest(text=text[:30]):
                with self.assertRaises(update.FeedError):
                    update.parse_feed(text)

    def test_sri(self):
        self.assertEqual(update.sri_from_feed(DEB_SHA), "sha512-" + DEB_SHA)
        for bad in ["abc", DEB_SHA[:-4] + "===="]:
            with self.subTest(bad=bad):
                with self.assertRaises(update.FeedError):
                    update.sri_from_feed(bad)

    def test_read_channel(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "app-update.yml")
            with open(path, "w") as f:
                f.write("provider: s3\nchannel: latest\npath: agent/linux\n")
            self.assertEqual(update.read_channel(path), "latest")
            self.assertEqual(update.read_channel(os.path.join(d, "missing.yml")), "beta")
        self.assertEqual(update.read_channel(None), "beta")

    def test_feed_url(self):
        self.assertEqual(
            update.feed_url("beta"),
            "https://downloads.oneleet.com/agent/linux/beta-linux.yml",
        )


class PinTests(unittest.TestCase):
    def test_write_pin_roundtrip(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "pin.json")
            update.write_pin(p, "2.5.0", "sha512-x")
            with open(p) as f:
                self.assertEqual(
                    f.read(), '{\n  "hash": "sha512-x",\n  "version": "2.5.0"\n}\n'
                )
            self.assertEqual(
                update.read_pin(p), {"hash": "sha512-x", "version": "2.5.0"}
            )
            self.assertEqual(os.listdir(d), ["pin.json"])


class RunTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.pin = os.path.join(self.tmp.name, "pin.json")
        self.logs = []
        self.builds = []

    def tearDown(self):
        self.tmp.cleanup()

    def write_pin(self, pin):
        with open(self.pin, "w") as f:
            json.dump(pin, f)

    def pin_text(self):
        with open(self.pin) as f:
            return f.read()

    def run_update(self, feed=FEED, build_ok=True, fetch_error=None):
        def fetch(_url):
            if fetch_error is not None:
                raise fetch_error
            return feed

        def build(version, hash_):
            self.builds.append((version, hash_))
            return build_ok

        return update.run(
            self.pin, update.feed_url("beta"), fetch, build, self.logs.append
        )

    def logged(self, text):
        return any(text in line for line in self.logs)

    def test_run_updates(self):
        self.write_pin(OLD_PIN)
        self.assertEqual(self.run_update(), 0)
        self.assertEqual(self.builds, [("2.5.0", "sha512-" + DEB_SHA)])
        self.assertEqual(
            update.read_pin(self.pin),
            {"version": "2.5.0", "hash": "sha512-" + DEB_SHA},
        )
        self.assertTrue(self.logged("2.0.0-beta.18 -> 2.5.0"), self.logs)

    def test_run_build_fails(self):
        self.write_pin(OLD_PIN)
        before = self.pin_text()
        self.assertEqual(self.run_update(build_ok=False), 0)
        self.assertEqual(self.pin_text(), before)
        self.assertTrue(self.logged("keeping 2.0.0-beta.18"), self.logs)

    def test_run_unreachable(self):
        self.write_pin(OLD_PIN)
        before = self.pin_text()
        self.assertEqual(self.run_update(fetch_error=TimeoutError("timed out")), 0)
        self.assertEqual(self.pin_text(), before)
        self.assertEqual(self.builds, [])
        self.assertTrue(self.logged("keeping 2.0.0-beta.18"), self.logs)

    def test_run_http_protocol_error(self):
        # urllib lets http.client errors from getresponse()/read() through
        # unwrapped; they are not OSErrors.
        self.write_pin(OLD_PIN)
        before = self.pin_text()
        error = http.client.IncompleteRead(b"partial")
        self.assertEqual(self.run_update(fetch_error=error), 0)
        self.assertEqual(self.pin_text(), before)
        self.assertEqual(self.builds, [])
        self.assertTrue(self.logged("keeping 2.0.0-beta.18"), self.logs)

    def test_run_same_version(self):
        self.write_pin({"version": "2.5.0", "hash": "sha512-" + DEB_SHA})
        before = self.pin_text()
        self.assertEqual(self.run_update(), 0)
        self.assertEqual(self.builds, [])
        self.assertEqual(self.pin_text(), before)

    def test_run_feed_older(self):
        self.write_pin({"version": "2.6.0", "hash": "sha512-newer"})
        before = self.pin_text()
        self.assertEqual(self.run_update(), 0)
        self.assertEqual(self.builds, [])
        self.assertEqual(self.pin_text(), before)

    def test_run_bad_feed_version(self):
        self.write_pin(OLD_PIN)
        before = self.pin_text()
        self.assertEqual(self.run_update(feed=feed_with_version("2.6.0+build.1")), 0)
        self.assertEqual(self.builds, [])
        self.assertEqual(self.pin_text(), before)
        self.assertTrue(self.logged("keeping 2.0.0-beta.18"), self.logs)

    def test_run_missing_pin(self):
        self.assertEqual(self.run_update(), 0)
        self.assertFalse(os.path.exists(self.pin))
        self.assertEqual(self.builds, [])
        self.assertTrue(self.logs)

    def test_run_corrupt_pin(self):
        with open(self.pin, "w") as f:
            f.write("{oops")
        self.assertEqual(self.run_update(), 0)
        self.assertEqual(self.pin_text(), "{oops")
        self.assertEqual(self.builds, [])
        self.assertTrue(self.logs)


class MainTests(unittest.TestCase):
    def test_main_usage(self):
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            self.assertEqual(update.main([]), 2)
        self.assertIn("required", err.getvalue())

    def test_main_last_nixpkgs_and_package_win(self):
        # The module's launcher passes defaults first; callers such as
        # os-rebuild append their own --nixpkgs/--package, which must win.
        calls = []

        def fake_run(_pin, _url, _fetch, build, _log):
            build("2.5.0", "sha512-x")
            return 0

        def fake_build(nixpkgs, package, version, hash_):
            calls.append((nixpkgs, package, version, hash_))
            return True

        with mock.patch.object(update, "run", side_effect=fake_run), mock.patch.object(
            update, "nix_test_build", side_effect=fake_build
        ):
            rc = update.main(
                ["--nixpkgs", "/default", "--package", "/default.nix",
                 "--nixpkgs", "/locked", "--package", "/locked.nix", "pin.json"]
            )
        self.assertEqual(rc, 0)
        self.assertEqual(calls, [("/locked", "/locked.nix", "2.5.0", "sha512-x")])

    def test_main_survives_unexpected_errors(self):
        # The never-block rule must hold even against bugs in run().
        err = io.StringIO()
        with mock.patch.object(update, "run", side_effect=RuntimeError("bug")):
            with contextlib.redirect_stderr(err):
                rc = update.main(["--nixpkgs", "/x", "--package", "/y", "pin.json"])
        self.assertEqual(rc, 0)
        self.assertIn("bug", err.getvalue())


if __name__ == "__main__":
    unittest.main()
