# Contributing / 参与贡献

Thank you for reviewing SHIXIN LAB · “CunJi” MacDisk Health. Before proposing a
change, read `README.md`, `Docs/ARCHITECTURE.md`, `SECURITY.md`, and the
repository `LICENSE`.

感谢你审查 SHIXIN LAB ·「存迹」MacDisk Health。提交修改前，请先阅读
`README.md`、`Docs/ARCHITECTURE.md`、`SECURITY.md` 与仓库 `LICENSE`。

## Contribution License / 贡献许可

By submitting a pull request, patch, or other code contribution, you agree to
license your contribution under `GPL-3.0-or-later`, unless a different written
agreement was accepted by SHIXIN LAB before submission. You retain copyright
in your original work and confirm that you have the right to submit it.

Do not submit copied code, generated output with incompatible terms, private
device data, or material whose license is unknown. Identify every newly added
third-party component and its exact license in the pull request.

提交 Pull Request、补丁或其他代码贡献，即表示你同意按
`GPL-3.0-or-later` 授权该贡献；除非提交前已与 SHIXIN LAB 达成其他书面约定。
你仍保留原创内容的版权，同时确认自己有权提交相关内容。

请勿提交来源不明的复制代码、许可证不兼容的生成内容、真实设备隐私数据或许可
状态不明确的材料。新增任何第三方组件时，必须在 Pull Request 中说明准确来源
与许可证。

The GPL contribution grant does not authorize replacement or reuse of official
SHIXIN LAB names, logos, app icons, or brand assets. See `TRADEMARKS.md`.

GPL 贡献授权不包含对 SHIXIN LAB 官方名称、Logo、App 图标或品牌素材的替换与
再利用许可，详见 `TRADEMARKS.md`。

## Non-Negotiable Safety Invariants / 不可突破的安全边界

- SMART access must remain read-only and pass through the fixed
  `SmartctlRunner` allowlist.
- Do not add shell execution, arbitrary smartctl arguments, raw-device writes,
  formatting, repair, mount/unmount, erase, or destructive fallback behavior.
- Speed tests may use only ordinary temporary files after explicit user
  confirmation and must retain cancellation and cleanup guarantees.
- Do not upload device data or expose serial numbers, UUIDs, UDIDs, full custom
  paths, or unredacted exports by default.
- Preserve the published Bundle ID and data migration invariants unless a
  separately reviewed release plan explicitly changes them.

- SMART 读取必须保持只读，并继续通过 `SmartctlRunner` 固定白名单。
- 不得加入 shell、任意 smartctl 参数、原始设备写入、格式化、修复、挂载/
  卸载、擦除或掩盖主流程错误的破坏性降级。
- 测速只能在用户明确确认后写普通临时文件，并保留取消与清理保证。
- 默认不得上传设备信息，也不得暴露序列号、UUID、UDID、完整自定义路径或
  未脱敏导出。
- 除非有单独审查的发布计划，不得改变正式 Bundle ID 与数据迁移不变量。

## Validation / 验证

Run at least:

```bash
Scripts/validate-public-repo.sh
swift run -c release ShixinDiskHealthSelfTest
swift build --triple arm64-apple-macosx15.0 -c release \
  --product ShixinDiskHealth -Xswiftc -warnings-as-errors
bash -n Scripts/*.sh
plutil -lint Packaging/Info.plist
git diff --check
```

GitHub Actions repeats the deterministic repository, self-test, and build
checks for every pull request and push to `main`. Changes involving real disks,
macOS integration, or interface behavior still require focused validation on a
real Mac.

GitHub Actions 会为每个 Pull Request 和对 `main` 的推送重复执行确定性的仓库、
自检与构建检查。涉及真实硬盘、macOS 集成或界面行为的修改，仍须在真实 Mac 上
完成针对性验证。

Changes to real SMART reads, disk identity, migration, speed measurement,
privacy export, packaging, or UI layout require focused tests and an explanation
of the preserved invariants. A successful compile alone is not release proof.

涉及真实 SMART 读取、硬盘身份、数据迁移、测速、隐私导出、打包或界面布局的
修改，必须补充针对性测试并说明保持了哪些不变量；仅“编译成功”不能作为发布
完成的证据。

## Pull Requests / Pull Request

Keep each change focused. Describe the user-visible result, the failure mode it
addresses, tests performed, and any remaining hardware or macOS-version limits.
Never include real private exports, local archives, DMGs, backups, credentials,
or user-specific absolute paths.

每次修改应保持范围清晰，并说明用户可见结果、修复的失效模式、已执行验证和
仍存在的硬件/macOS 边界。不得提交真实隐私导出、本地归档、DMG、备份、凭据
或用户专属绝对路径。

Each pull request must also confirm that the contribution is offered under
`GPL-3.0-or-later` and list any third-party code or assets it introduces.

每个 Pull Request 还必须确认贡献采用 `GPL-3.0-or-later`，并列出本次引入的
全部第三方代码或素材。
