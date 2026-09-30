#!/usr/bin/env python3
# Copyright (C) 2026 SHIXIN LAB / Shixin
# SPDX-License-Identifier: GPL-3.0-or-later
"""Verify the shipping updater configuration without contacting its server."""
import argparse
import base64
import hashlib
import os
import plistlib
import re
import subprocess
from pathlib import Path


FEED = "https://shixinqvq.com/lab/macdisk/updates/appcast.xml"
POLICY = {
    "SUEnableAutomaticChecks": False, "SUAutomaticallyUpdate": False,
    "SUAllowsAutomaticUpdates": False, "SUEnableSystemProfiling": False,
    "SUEnableJavaScript": False, "SUVerifyUpdateBeforeExtraction": True,
    "SURequireSignedFeed": True, "SUSignedFeedFailureExpirationInterval": 0,
}


def validate(info, require_key):
    if info.get("SUFeedURL") != FEED:
        raise ValueError("Unexpected production update URL")
    for key, value in POLICY.items():
        if key not in info or info[key] != value:
            raise ValueError("Unexpected updater policy: " + key)
    if any(key.startswith("CunJiReview") for key in info) or "LSEnvironment" in info:
        raise ValueError("Test environment must not enter a release")
    if info.get("CFBundleIdentifier") != "com.shixinqvq.shixinlab.diskhealth":
        raise ValueError("Unexpected product bundle identifier")
    key = info.get("SUPublicEDKey")
    if require_key or key is not None:
        if not isinstance(key, str) or len(base64.b64decode(key, validate=True)) != 32:
            raise ValueError("A valid product Ed25519 public key is required")
    if require_key and int(info["CFBundleVersion"]) <= 6:
        raise ValueError("The first update-enabled release needs a new build above 6")
    return hashlib.sha256(base64.b64decode(key)).hexdigest() if key else "not configured (development only)"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--require-key", action="store_true")
    args = parser.parse_args()
    contents = args.app / "Contents"
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    fingerprint = validate(info, args.require_key)
    build_info = subprocess.check_output([
        "xcrun", "vtool", "-show-build", str(contents / "MacOS/ShixinDiskHealth")
    ], text=True)
    sdk_path = Path(os.environ.get("SHIXIN_BUILD_SDK_PATH", "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"))
    sdk = plistlib.loads((sdk_path / "SDKSettings.plist").read_bytes())["Version"]
    versions = re.findall(r"^\s+sdk\s+(\S+)", build_info, re.MULTILINE)
    def version_tuple(value):
        return tuple((list(map(int, value.split("."))) + [0, 0])[:3])
    if not versions or any(version_tuple(value) != version_tuple(sdk) for value in versions):
        raise ValueError(f"Linked SDK {versions} does not match build SDK {sdk}; use Scripts/swift-build.sh")
    framework = contents / "Frameworks/Sparkle.framework"
    metadata = plistlib.loads((framework / "Resources/Info.plist").read_bytes())
    if metadata["CFBundleShortVersionString"] != "2.10.0":
        raise ValueError("Unexpected Sparkle framework version")
    linked = subprocess.check_output(["otool", "-L", str(contents / "MacOS/ShixinDiskHealth")], text=True)
    if "@rpath/Sparkle.framework/Versions/B/Sparkle" not in linked:
        raise ValueError("Missing relocatable Sparkle dependency")
    if any("Sparkle.framework" in line and "@rpath/" not in line for line in linked.splitlines()[1:]):
        raise ValueError("Sparkle dependency references an external location")
    if not (contents / "Resources/Licenses/Sparkle-LICENSE.txt").is_file():
        raise ValueError("Sparkle license is missing")
    for language in ["en", "ja", "zh-Hans"]:
        for filename in ["Localizable.strings", "InfoPlist.strings"]:
            resource = contents / "Resources" / (language + ".lproj") / filename
            if not resource.is_file() or resource.stat().st_size == 0:
                raise ValueError("Missing localization: " + str(resource))
    if b"Updater test build requires its isolated review home" in (contents / "MacOS/ShixinDiskHealth").read_bytes():
        raise ValueError("Review executable must never ship")
    executable = contents / "MacOS/ShixinDiskHealth"
    binary = executable.read_bytes()
    if b"http://127.0.0.1" in binary or b"http://localhost" in binary:
        raise ValueError("Local update feed must not enter a release executable")
    if re.findall(r"^\s+minos\s+(\S+)", build_info, re.MULTILINE) != ["15.0"]:
        raise ValueError("Unexpected minimum macOS version")
    if subprocess.check_output(["lipo", "-archs", str(executable)], text=True).strip() != "arm64":
        raise ValueError("Unexpected release architecture")
    if info.get("CFBundleIconFile") != "AppIconV2":
        raise ValueError("Published icon identity changed")
    for key in ["SHIXINAppSupportDirectoryName", "SHIXINSpeedTestCacheDirectoryName"]:
        if info.get(key) != "SHIXIN LAB MacDisk Health":
            raise ValueError("Published data namespace changed: " + key)
    if (contents / "Library/LaunchDaemons").exists():
        raise ValueError("Product hardware Helper must remain absent")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(args.app)], check=True)
    print("Updater bundle verified; public-key SHA-256: " + fingerprint)


if __name__ == "__main__":
    main()
