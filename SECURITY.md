# Security Policy / 安全策略

## Supported Release / 当前支持版本

Security fixes are evaluated against the latest published `0.2.x` source and
release package. Older beta builds may be used for comparison but are not the
primary remediation target.

安全问题以最新公开的 `0.2.x` 源码和正式安装包为主要修复对象；旧 Beta 版本
可用于对比，但不作为首要维护目标。

## Reporting A Vulnerability / 报告漏洞

Please do not publish a working exploit, disk serial number, raw SMART export,
Provisioning UDID, platform UUID, full local path, or other private device data
in a public issue.

请勿在公开 Issue 中发布可直接利用的攻击步骤、硬盘序列号、原始 SMART 导出、
Provisioning UDID、平台 UUID、完整本机路径或其他隐私设备信息。

Use this repository's enabled GitHub private vulnerability reporting flow. If
GitHub is temporarily unavailable, contact SHIXIN LAB through the official site
first and provide only a minimal, redacted summary until a private channel is
agreed:

本仓库已启用 GitHub 私密漏洞报告，请优先使用；若 GitHub 暂时不可用，请先通过
SHIXIN LAB 官网联系，并仅提交经过脱敏的最小摘要，待双方确认私密沟通渠道后再
提供复现细节：

- Private vulnerability report / 私密漏洞报告:
  [Open the private report form](https://github.com/ShiXinQvQ/SHIXIN-LAB-CunJi-MacDisk-Health/security/advisories/new)
- Official website / 官方网站: https://shixinqvq.com/

Useful reports include the affected version/build, macOS version, Mac model,
expected and actual behavior, minimal reproduction steps, and whether the issue
crosses the documented read-only or privacy boundary.

有效报告应包含：受影响版本/build、macOS 版本、Mac 型号、预期与实际行为、
最小复现步骤，以及问题是否突破了文档中的只读或隐私边界。

## Release Integrity / 发布完整性

Official release artifacts are distributed through SHIXIN LAB channels. Verify
the downloaded DMG or ZIP against the SHA-256 value published beside that exact
artifact. Do not reuse a checksum from an older timestamped package.

- Official Releases: https://github.com/ShiXinQvQ/SHIXIN-LAB-CunJi-MacDisk-Health/releases
- Checksum manifest: [SHA256SUMS.txt](SHA256SUMS.txt)
- Product page: https://shixinqvq.com/lab/macdisk/

正式安装包只通过 SHIXIN LAB 官方渠道发布。请使用与目标 DMG/ZIP 同时公布的
SHA-256 校验值核对文件，不要沿用旧时间戳版本的哈希。

- 官方 Releases：https://github.com/ShiXinQvQ/SHIXIN-LAB-CunJi-MacDisk-Health/releases
- 校验清单：[SHA256SUMS.txt](SHA256SUMS.txt)
- 产品官网：https://shixinqvq.com/lab/macdisk/
