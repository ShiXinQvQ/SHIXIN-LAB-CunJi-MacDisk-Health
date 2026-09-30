#!/usr/bin/env python3
# Copyright (C) 2026 SHIXIN LAB / Shixin
# SPDX-License-Identifier: GPL-3.0-or-later
"""Embed the pinned SPM artifact; retain its bundle layout and sign inside-out."""
import argparse
import plistlib
import shutil
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch", type=Path, required=True)
    parser.add_argument("--app", type=Path, required=True)
    args = parser.parse_args()
    artifact = args.scratch / "artifacts/sparkle/Sparkle"
    xcframework = artifact / "Sparkle.xcframework"
    metadata = plistlib.loads((xcframework / "Info.plist").read_bytes())
    matches = [item for item in metadata["AvailableLibraries"]
               if item["SupportedPlatform"] == "macos" and not item.get("SupportedPlatformVariant")]
    if len(matches) != 1:
        raise SystemExit("Expected one macOS Sparkle framework")
    item = matches[0]
    source = xcframework / item["LibraryIdentifier"] / item["LibraryPath"]
    version = plistlib.loads((source / "Resources/Info.plist").read_bytes())["CFBundleShortVersionString"]
    if version != "2.10.0":
        raise SystemExit("Unexpected Sparkle version: " + version)
    executable = args.app / "Contents/MacOS/ShixinDiskHealth"
    architectures = subprocess.check_output(["lipo", "-archs", str(executable)], text=True).split()
    if not set(architectures).issubset(item["SupportedArchitectures"]):
        raise SystemExit("Sparkle does not support every App architecture")
    target = args.app / "Contents/Frameworks/Sparkle.framework"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source, target, symlinks=True)
    license_dir = args.app / "Contents/Resources/Licenses"
    license_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(artifact / "LICENSE", license_dir / "Sparkle-LICENSE.txt")
    for relative in ["Versions/B/XPCServices/Downloader.xpc", "Versions/B/XPCServices/Installer.xpc",
                     "Versions/B/Updater.app", "Versions/B/Autoupdate", "."]:
        subprocess.run(["codesign", "--force", "--sign", "-", str(target / relative)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(target)], check=True)
    linked = subprocess.check_output(["otool", "-L", str(executable)], text=True)
    if "@rpath/Sparkle.framework/Versions/B/Sparkle" not in linked:
        raise SystemExit("App is not linked to the bundled Sparkle framework")
    print("Embedded Sparkle " + version)


if __name__ == "__main__":
    main()
