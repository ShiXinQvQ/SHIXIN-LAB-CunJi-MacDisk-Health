# CunJi 0.3.0 Beta (build 7)

## Changes

- macOS 27 only: stable card surfaces and the original blue sidebar selection. Other appearance branches, window sizes and AppIconV2 remain unchanged.
- Shared across supported systems: Sparkle 2.10.0 in-app updates, off-by-default automatic checks, independent Ed25519 signatures, and task/termination coordination.
- Include all three existing language resources in the app bundle.
- Preserve supplemental SMART health-failure exit bits instead of masking them behind a successful core response.
- Keep the hardware Helper disabled; retain fixed read-only SMART commands and existing data namespaces.

## Verification and limits

On macOS 27: nine focused XCTest cases passed (appearance routing, update task coordination, repeated quit, SMART failure merging). Twenty-nine deterministic business self-tests passed in an isolated test harness with recoverable temporary-file cleanup. Fifteen negative package-policy cases passed. The final DMG was verified and mounted read-only; all 116 app files and links matched the packaged candidate.

An isolated simulated update installed and restarted successfully, matched every candidate file, preserved a saved snapshot, and then reported the current version. This was not a public 0.2.0 upgrade: 0.2.0 has no updater and requires one manual installation. Invalid HTML feeds, damaged archives, HTTP failures, older versions and incompatible system requirements were exercised.

All six main pages, independent Settings, and Chinese/English/Japanese text were checked on macOS 27. macOS 26 visual testing was not performed; source isolation and 15/26/27/28 routing tests do not replace that test. No full 1 GB speed test was run while the computer was in concurrent use. Unwritable-target and disk-full updater simulations were not completed. These are validation limits, not claims of failure or universal compatibility.

## Install

Use the single DMG on the v0.3.0 Release. It supports Apple Silicon and macOS 15 or later. Preserve the existing app data and preferences; no reset is required. The first installation from 0.2.0 is manual. Subsequent signed releases can be installed through Settings.

SHA-256: `acadde679a1dc40e0f27f1b96eeedd2ee212dd274e633da784b76e38e07312e4`
