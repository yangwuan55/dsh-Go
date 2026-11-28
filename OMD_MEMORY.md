# OMD Memory

## 测试纪律 / test-budget

- 标签：`workflow/test-budget`（约定）
- 内容：不要做全量测试，太浪费时间；只跑受影响范围的最小定向验证（相关文件 analyze、单个测试文件或单个用例）。
- 日期：2026-11-28
- 为什么重要：用户 (m00880) 明确要求；全量 `flutter analyze` / `flutter test` 在本仓库耗时很长，会拖慢调试与修复。
