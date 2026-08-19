# Architecture and Safety Model / 架构与安全模型

This document describes the public `0.2.0` architecture without relying on a
specific developer Mac, test disk, or internal build history.

本文说明公开版本 `0.2.0` 的正式架构，不依赖某一台开发用 Mac、测试硬盘或
内部构建过程。

## Product Boundary / 产品边界

CunJi is a local-first macOS viewer and diagnostic utility. It reads disk
health information, stores local history, performs user-confirmed ordinary-file
speed tests, and displays fixed read-only system information. It is not a disk
repair, formatting, recovery, or remote-monitoring service.

「存迹」是一款本地优先的 macOS 查看与诊断工具：读取硬盘健康信息、保存本机
历史、执行用户明确确认的普通文件测速，并展示固定只读系统信息。它不是磁盘
修复、格式化、数据恢复或远程监控服务。

## Components / 组件

- `ShixinDiskHealth`: SwiftUI application and presentation state.
- `ShixinDiskHealthCore`: disk inventory, fixed-command execution, parsing,
  health evaluation, snapshots, exports, and speed-test implementation.
- `ShixinDiskHealthSelfTest`: deterministic safety, parsing, migration,
  redaction, process, and speed-test checks.
- `ShixinDiskHealthPrivilegedHelper`: an inactive, fail-closed development
  skeleton. It rejects every XPC connection and is not embedded, installed,
  registered, or called by the `0.2.0` release. Any future activation requires
  a separate signed-client authentication and release review.
- `smartmontools / smartctl 7.5`: third-party GPL-2.0-or-later component used
  only through the fixed read-only policy described below.

- `ShixinDiskHealth`：SwiftUI App 与界面状态。
- `ShixinDiskHealthCore`：硬盘枚举、固定命令执行、解析、健康判断、快照、导出
  与测速实现。
- `ShixinDiskHealthSelfTest`：确定性的安全、解析、迁移、脱敏、进程与测速自检。
- `ShixinDiskHealthPrivilegedHelper`：未启用且默认拒绝连接的开发骨架；`0.2.0`
  不内置、不安装、不注册，也不会调用它。未来若要启用，必须另行完成已签名调用方
  身份验证与发布审查。
- `smartmontools / smartctl 7.5`：第三方 GPL-2.0-or-later 组件，仅通过下述固定
  只读策略调用。

## SMART Read Flow / SMART 读取流程

```text
DiskArbitration inventory
        ↓
physical whole-disk and identity validation
        ↓
bundled or explicitly located smartctl
        ↓
fixed read-only argument allowlist
        ↓
bounded process execution and JSON parsing
        ↓
protocol-specific health evaluation
        ↓
local display, snapshot, and redacted export
```

Every real read is revalidated against a fresh native inventory. Only
enumerated physical whole-disk `/dev/diskN` targets are accepted. Partitions,
`rdisk`, arbitrary paths, shell strings, and caller-provided smartctl arguments
are rejected. Auto mode omits `-d`; an explicit device type is limited to the
small, enumerated allowlist documented in the README.

每次真实读取都会重新核对当前原生硬盘枚举。只接受已枚举的物理 whole-disk
`/dev/diskN`；分区、`rdisk`、任意路径、shell 字符串和调用方自定义 smartctl
参数都会被拒绝。Auto 模式不传 `-d`；显式设备类型只能来自 README 中列出的
固定小型白名单。

Core health and supplemental read completeness are evaluated separately. A
bridge or Apple controller that does not expose an optional log is reported as
limited or unavailable; that condition does not become a fabricated disk
failure or another disk's report.

核心健康与附加读取完整性分别判断。硬盘盒或 Apple 控制器不提供可选日志时，
会显示“受限”或“不可用”，不会伪造成硬盘故障，也不会套用其他硬盘的报告。

## Speed-Test Flow / 测速流程

Speed testing is isolated from SMART execution. After explicit confirmation it
creates a fixed-size ordinary temporary file in an allowed cache or selected
folder, measures sequential Swift file I/O, requests cache bypass and durable
write confirmation where supported, and removes the test file. It never opens
or writes a raw `/dev/*` device and never invokes `dd`, `diskutil`, `fsck`,
repair, erase, mount, or format commands.

测速与 SMART 执行相互隔离。用户明确确认后，App 只在允许的缓存目录或所选普通
文件夹创建固定大小的临时文件，使用 Swift 顺序文件 I/O 测量速度，在系统支持
时请求绕过缓存并确认写入持久化，最后清理测试文件。它绝不会打开或写入 raw
`/dev/*` 设备，也不会调用 `dd`、`diskutil`、`fsck`、修复、擦除、挂载或格式化
命令。

## Local Data and Privacy / 本机数据与隐私

Snapshots, speed-test records, and the interrupted-test cleanup ledger stay in
the user's Library directories described in the README. No background upload
or analytics path exists. Device identifiers are hidden in the interface by
default, raw SMART export is redacted by default, and custom speed-test folder
paths are not retained in history.

快照、测速记录和中断测速清理清单只保存在 README 所列的用户 Library 目录中。
App 不存在后台上传或分析统计通道。设备标识默认在界面隐藏，SMART 原始导出
默认脱敏，测速历史也不会保存自定义文件夹的完整路径。

## Release Identity / 发布身份

The official `0.2.0` release uses:

- App name: `SHIXIN LAB · 「存迹」`
- Bundle ID: `com.shixinqvq.shixinlab.diskhealth`
- Data namespace: `SHIXIN LAB MacDisk Health`
- Minimum system: macOS 15
- Architecture: Apple Silicon (`arm64`)
- Privileged helper: not included

The build script requires explicit environment variables before it will create
the published identity. This prevents an ordinary development command from
overwriting the installed release or its data namespace.

正式 `0.2.0` 使用上述固定 App 名称、Bundle ID、数据命名空间、macOS 15 最低
版本和 Apple Silicon 架构，且不包含特权 Helper。构建脚本只有收到明确环境
变量后才会生成正式身份，避免普通开发命令覆盖已安装正式版或其数据目录。

## Validation / 验证

The release gate includes deterministic self-tests, a warnings-as-errors
Release build, shell and plist validation, packaged-App identity checks, strict
code-structure verification, DMG verification, mounted-content inspection, ZIP
integrity, and SHA-256 comparison. Hardware-specific SMART availability remains
dependent on macOS and the storage bridge and must be tested on the target
hardware.

Every pull request and push to `main` also runs deterministic repository,
localization, bundled-component, self-test, and Apple Silicon build checks in
GitHub Actions. These automated checks protect reproducible invariants; they do
not replace real-Mac hardware and visual acceptance testing.

发布门禁包括确定性自检、将警告视为错误的 Release 构建、shell 与 plist 校验、
App 身份检查、严格代码结构验证、DMG 校验、挂载内容核查、ZIP 完整性和 SHA-256
比对。特定硬件能否提供 SMART 仍取决于 macOS 与硬盘桥接器，需要在目标硬件上
实际验证。

每个 Pull Request 以及对 `main` 的推送还会在 GitHub Actions 中执行确定性的仓库、
本地化、内置组件、自检与 Apple Silicon 构建检查。自动检查用于守住可重复验证的
不变量，但不能替代真实 Mac 硬件测试与界面验收。

## Licensing / 许可

SHIXIN LAB-owned code and documentation are GPL-3.0-or-later. The official
names, logos, icons, Bundle ID, and source-identifying brand assets are governed
separately by `COPYRIGHT.md` and `TRADEMARKS.md`. Third-party components retain
their own licenses and notices under `Licenses/`.

SHIXIN LAB 自有代码与文档采用 GPL-3.0-or-later。官方名称、Logo、图标、Bundle
ID 和用于识别来源的品牌素材由 `COPYRIGHT.md` 与 `TRADEMARKS.md` 单独约束；
第三方组件继续适用 `Licenses/` 中各自的许可证与声明。
