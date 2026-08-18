# Changelog / 更新日志

## 0.2.0 (build 6) — 2026-08-18

- Promoted the final app identity to `SHIXIN LAB · 「存迹」` while preserving
  Bundle ID `com.shixinqvq.shixinlab.diskhealth` and the published data namespace.
- Added safe one-time reconciliation of missing SMART snapshots and speed-test
  records from the retired internal-v2 namespace without rewriting source data.
- Strengthened internal/external whole-disk discovery, protocol-specific SMART
  interpretation, wrong-device rejection, read-completeness reporting, export
  redaction, process limits, and cancellation guards.
- Kept SMART commands behind the fixed read-only allowlist; external bridges
  that do not expose SMART are reported unavailable rather than failed.
- Updated the sequential-file speed runner so buffer preparation, UI progress
  delivery, and durability confirmation do not inflate measured throughput.
- Changed speed-history chart spacing to saved-test order while retaining real
  date/time labels, preventing same-minute points from collapsing into spikes.
- Refined report, history, speed-test, and Settings layouts and added consistent
  information buttons for previously unexplained metrics.
- Added formal bilingual installation, product/copyright, and release documents,
  plus the corresponding smartmontools 7.5 source archive and checksum checks.
- Published the SHIXIN LAB-owned source and documentation under
  `GPL-3.0-or-later`, with separate trademark and brand-asset protections.

- 正式 App 身份统一为 `SHIXIN LAB ·「存迹」`，同时保留正式 Bundle ID 与数据
  命名空间。
- 安全合并已退役内部 v2 中缺少的 SMART 快照和测速记录，不改写迁移源文件。
- 加固内/外置 whole-disk 枚举、协议对应健康解释、错盘拒绝、读取完整性、
  导出脱敏、进程上限与取消保护。
- SMART 继续只允许固定只读参数；不透传 SMART 的外置桥接器显示“不可用”，
  不误报硬盘故障。
- 测速计时不再混入缓冲区准备、界面进度回调和持久化确认等待。
- 趋势图按已保存测试顺序等距展示并保留真实日期时间，避免同一分钟结果重叠
  成竖线或尖峰。
- 优化报告、历史、测速与设置排版，并为此前缺少解释的指标补齐信息按钮。
- 正式 DMG 加入双语安装、产品版权、版本说明及 smartmontools 7.5 对应源码和
  校验门禁。
- SHIXIN LAB 自有源码与文档正式采用 `GPL-3.0-or-later`，同时以独立政策保护
  商标、产品名称、Logo、App 图标与品牌素材。

## 0.1.1 Beta

- Initial public baseline for internal Apple SSD SMART/NVMe health, local
  snapshots, history/export, hardware profile, and ordinary-file speed tests.
