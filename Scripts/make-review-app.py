#!/usr/bin/env python3
# Copyright (C) 2026 SHIXIN LAB / Shixin
# SPDX-License-Identifier: GPL-3.0-or-later
"""Assemble a double-clickable, isolated local review app; never a release bundle."""
import argparse
import base64
import binascii
import plistlib
import shutil
import subprocess
from pathlib import Path
from urllib.parse import urlparse


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-app", required=True, type=Path)
    parser.add_argument("--test-executable", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--home", required=True, type=Path)
    parser.add_argument("--build", required=True, type=int)
    parser.add_argument("--feed-url")
    parser.add_argument("--public-key")
    args = parser.parse_args()
    if bool(args.feed_url) != bool(args.public_key):
        parser.error("Provide both --feed-url and --public-key, or neither")
    if args.public_key:
        try:
            valid_key = len(base64.b64decode(args.public_key, validate=True)) == 32
        except (ValueError, binascii.Error):
            valid_key = False
        if not valid_key:
            parser.error("Public key must be exactly 32 base64-encoded bytes, not tool output")
        url = urlparse(args.feed_url)
        if url.scheme != "http" or url.hostname not in {"127.0.0.1", "localhost"}:
            parser.error("Review feed must use HTTP on localhost")
    output, home = args.output.resolve(), args.home.resolve()
    if output.exists() or output.suffix != ".app":
        raise SystemExit("Output must be a new .app path; existing apps are never overwritten")
    if args.build <= 6:
        raise SystemExit("Use a distinct local review build above 6")
    if home == Path.home() or home == output or output in home.parents:
        raise SystemExit("Review home must be isolated and outside the app bundle")
    marker = b"Updater test build requires its isolated review home"
    if marker not in args.test_executable.read_bytes():
        raise SystemExit("Expected a SHIXIN_UPDATE_TESTING executable with its isolation guard")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(args.base_app)], check=True)
    home.mkdir(parents=True, exist_ok=True)
    shutil.copytree(args.base_app, output, symlinks=True)
    contents = output / "Contents"
    shutil.copy2(args.test_executable, contents / "MacOS/ShixinDiskHealth")
    path = contents / "Info.plist"
    info = plistlib.loads(path.read_bytes())
    info.update({
        "CFBundleIdentifier": "com.shixinqvq.shixinlab.diskhealth.review.updater",
        "CFBundleName": output.stem, "CFBundleDisplayName": output.stem,
        "CFBundleVersion": str(args.build),
        "CFBundleShortVersionString": "0.3.0-review",
        "CunJiReviewHome": str(home),
        "LSEnvironment": {"CFFIXED_USER_HOME": str(home)},
        "SUEnableAutomaticChecks": False,
        "SHIXINAppSupportDirectoryName": "SHIXIN LAB MacDisk Health review",
        "SHIXINSpeedTestCacheDirectoryName": "SHIXIN LAB MacDisk Health review",
    })
    # Local review is not permitted to contact or install from a production feed.
    info.pop("SUPublicEDKey", None)
    info.pop("SUFeedURL", None)
    if args.feed_url:
        info["SUFeedURL"] = args.feed_url
        info["SUPublicEDKey"] = args.public_key
        info["NSAppTransportSecurity"] = {"NSAllowsLocalNetworking": True}
    path.write_bytes(plistlib.dumps(info))
    subprocess.run(["codesign", "--force", "--sign", "-", str(output)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(output)], check=True)
    print(output)


if __name__ == "__main__":
    main()
