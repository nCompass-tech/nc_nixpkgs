"""oneleet-update: move a Oneleet pin file to the newest release in Oneleet's feed.

Rules this script must keep:
- It never stops a rebuild. Every outcome (feed unreachable, unparsable, no
  newer version, failed test build, bad pin file) exits 0 with a warning and
  leaves the pin untouched; only a usage error exits 2.
- The pin only moves forward, and only after the candidate version was built
  with Nix. Ordering is semver precedence, written out here because both
  `sort -V` and `builtins.compareVersions` rank 2.6.0 below 2.6.0-beta.3.
- The feed is read with a small strict parser (standard library only); any
  surprise in its shape counts as "unparsable" and keeps the current pin.
"""

import argparse
import base64
import binascii
import http.client
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
from dataclasses import dataclass
from typing import Callable, Optional

FEED_BASE = "https://downloads.oneleet.com/agent/linux"
USER_AGENT = "oneleet-update (nc_nixpkgs)"
DEFAULT_CHANNEL = "beta"

_SEMVER = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$")


class FeedError(Exception):
    """The update feed is missing something or has an unexpected shape."""


@dataclass(frozen=True)
class FeedEntry:
    version: str
    deb_name: str
    sha512: str


def semver_key(version: str) -> tuple:
    match = _SEMVER.match(version)
    if not match:
        raise ValueError(f"not a MAJOR.MINOR.PATCH[-prerelease] version: {version!r}")
    major, minor, patch, pre = match.groups()
    ids = ()
    if pre is not None:
        parts = pre.split(".")
        if any(p == "" for p in parts):
            raise ValueError(f"empty prerelease identifier in {version!r}")
        ids = tuple((0, int(p)) if p.isdigit() else (1, p) for p in parts)
    return (int(major), int(minor), int(patch), pre is None, ids)


def is_newer(candidate: str, current: str) -> bool:
    return semver_key(candidate) > semver_key(current)


def _value(line: str, key: str) -> Optional[str]:
    prefix = f"{key}:"
    if not line.startswith(prefix):
        return None
    return line[len(prefix):].strip().strip("'\"")


def parse_feed(text: str) -> FeedEntry:
    version = None
    files = []
    in_files = False
    for raw in text.splitlines():
        if not raw.strip():
            continue
        if not raw.startswith(" "):
            in_files = raw.rstrip() == "files:"
            if raw.startswith("version:"):
                version = _value(raw, "version")
            elif not in_files and ":" not in raw:
                raise FeedError(f"unexpected feed line: {raw!r}")
            continue
        if not in_files:
            raise FeedError(f"unexpected indented feed line: {raw!r}")
        line = raw.strip()
        if line.startswith("- "):
            files.append({})
            line = line[2:].strip()
        if not files or ":" not in line:
            raise FeedError(f"unexpected entry in files: {raw!r}")
        key, _, val = line.partition(":")
        files[-1][key.strip()] = val.strip().strip("'\"")
    if not version:
        raise FeedError("feed has no version")
    debs = [f for f in files if f.get("url", "").endswith("_amd64.deb")]
    if len(debs) != 1 or not debs[0].get("sha512"):
        raise FeedError("feed has no single amd64 .deb entry with a sha512")
    return FeedEntry(version, debs[0]["url"], debs[0]["sha512"])


def sri_from_feed(sha512_b64: str) -> str:
    try:
        digest = base64.b64decode(sha512_b64, validate=True)
    except (binascii.Error, ValueError) as e:
        raise FeedError(f"sha512 is not valid base64: {e}") from e
    if len(digest) != 64:
        raise FeedError(f"sha512 decodes to {len(digest)} bytes, expected 64")
    return "sha512-" + sha512_b64


def read_channel(app_update_yml: Optional[str]) -> str:
    if not app_update_yml:
        return DEFAULT_CHANNEL
    try:
        with open(app_update_yml) as f:
            for line in f:
                value = _value(line.strip(), "channel")
                if value:
                    return value
    except OSError:
        pass
    return DEFAULT_CHANNEL


def feed_url(channel: str) -> str:
    return f"{FEED_BASE}/{channel}-linux.yml"


def read_pin(path: str) -> dict:
    with open(path) as f:
        pin = json.load(f)
    if not isinstance(pin, dict) or not isinstance(pin.get("version"), str) or not isinstance(pin.get("hash"), str):
        raise ValueError(f"{path} must hold string fields 'version' and 'hash'")
    return pin


def write_pin(path: str, version: str, hash_: str) -> None:
    directory = os.path.dirname(os.path.abspath(path))
    fd, tmp = tempfile.mkstemp(prefix=".pin-", suffix=".tmp", dir=directory)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump({"version": version, "hash": hash_}, f, indent=2, sort_keys=True)
            f.write("\n")
        if os.path.exists(path):
            os.chmod(tmp, os.stat(path).st_mode & 0o777)
        else:
            os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass
        raise


def run(
    pin_path: str,
    url: str,
    fetch: Callable[[str], str],
    build: Callable[[str, str], bool],
    log: Callable[[str], None],
) -> int:
    try:
        pin = read_pin(pin_path)
        semver_key(pin["version"])
    except (OSError, ValueError) as e:
        log(f"oneleet-update: cannot read pin file {pin_path}: {e}; leaving it unchanged")
        return 0
    current = pin["version"]

    try:
        entry = parse_feed(fetch(url))
        candidate_hash = sri_from_feed(entry.sha512)
        newer = is_newer(entry.version, current)
    except (OSError, ValueError, FeedError, http.client.HTTPException) as e:
        # urllib passes http.client errors from reading the response through
        # unwrapped; they are not OSErrors.
        log(f"oneleet-update: cannot use the update feed {url}: {e!r}; keeping {current}")
        return 0

    if not newer:
        log(f"oneleet-update: Oneleet {current} is current (feed offers {entry.version})")
        return 0

    log(f"oneleet-update: test-building Oneleet {entry.version}")
    try:
        built = build(entry.version, candidate_hash)
    except OSError as e:
        log(f"oneleet-update: could not run the test build: {e}")
        built = False
    if not built:
        log(f"oneleet-update: Oneleet {entry.version} did not build; keeping {current}")
        return 0

    try:
        write_pin(pin_path, entry.version, candidate_hash)
    except OSError as e:
        log(f"oneleet-update: cannot write {pin_path}: {e}; keeping {current}")
        return 0
    log(f"oneleet-update: Oneleet {current} -> {entry.version}")
    return 0


def fetch_feed(url: str, timeout: float = 20.0) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read(1 << 20).decode("utf-8")


def nix_test_build(nixpkgs: str, package: str, version: str, hash_: str) -> bool:
    expr = (
        "{ nixpkgs, package, version, hash }: "
        "(import nixpkgs { config.allowUnfree = true; }).callPackage package { inherit version hash; }"
    )
    result = subprocess.run(
        [
            "nix-build", "--no-out-link", "-E", expr,
            "--arg", "nixpkgs", nixpkgs,
            "--arg", "package", package,
            "--argstr", "version", version,
            "--argstr", "hash", hash_,
        ],
        stdout=sys.stderr,
    )
    return result.returncode == 0


class _Parser(argparse.ArgumentParser):
    def error(self, message):
        self.print_usage(sys.stderr)
        print(f"{self.prog}: error: {message}", file=sys.stderr)
        raise _UsageError


class _UsageError(Exception):
    pass


def main(argv: list) -> int:
    parser = _Parser(
        prog="oneleet-update",
        description="Move a Oneleet pin file to the newest release in Oneleet's feed.",
    )
    parser.add_argument("--nixpkgs", required=True, help="nixpkgs source used for the test build")
    parser.add_argument("--package", required=True, help="Oneleet package.nix used for the test build")
    parser.add_argument("--app-update-yml", help="installed app-update.yml; its channel picks the feed")
    parser.add_argument("--feed-url", help="override the feed URL (testing)")
    parser.add_argument("pin_file", help="JSON pin file with 'version' and 'hash'")
    try:
        args = parser.parse_args(argv)
    except _UsageError:
        return 2

    url = args.feed_url or feed_url(read_channel(args.app_update_yml))

    def build(version: str, hash_: str) -> bool:
        return nix_test_build(args.nixpkgs, args.package, version, hash_)

    def log(message: str) -> None:
        print(message, file=sys.stderr)

    try:
        return run(args.pin_file, url, fetch_feed, build, log)
    except Exception as e:  # never block a rebuild, even on a bug here
        log(f"oneleet-update: unexpected error: {e!r}; leaving the pin unchanged")
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
