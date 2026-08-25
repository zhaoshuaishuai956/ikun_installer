# ikun_dev_standard — 爱坤工具箱整体开发规范（L3 权威源）

本仓是《爱坤工具箱（ikun）整体开发规范》v1.0 的**唯一权威存放点**（规范 §2.2）。

## What — 做什么

- `ikun-整体开发规范-v1.0.md` — L3 权威源：ikun 生态（ikun_installer 中心 + 11 个 NX 插件 + 知识库）的整体协同规则
- `registry.json` — 附录 A 全量仓库清册的**机器形态**（由 `scripts/verify-repo.ps1` 扫描生成，禁止手工维护）
- `docs/adversarial-review/` — v1.0 发布前的三轮红队审查报告（一致性/安全/落地性）
- `scripts/verify-repo.ps1` — 合规真值表扫描工具（M7b）

## Why — 为什么

规范 §0 盘点了生态的 11 类问题（4 处事实源漂移、9 仓缺 CHANGELOG、制品无溯源、GBK 菜单无守卫、
更新链无签名等）。本仓让「谁说了算」有一个唯一答案，并让规则可被机器检查。

## Run — 如何用

1. 读 `ikun-整体开发规范-v1.0.md`（L3 权威；L1=gitea-for-ai，L2=nx_dev_skill，冲突时 L3>L2>L1）
2. 本地开发：`pwsh scripts/verify-repo.ps1 -ReposRoot <克隆根目录>` 扫描合规真值表
3. 新插件登记：改 `registry.json` 后提交 PR（或跑 verify-repo.ps1 重新生成）

## Test — 测试

- `verify-repo.ps1` 自检：`pwsh scripts/verify-repo.ps1 -SelfTest`
- 镜像链一致性：`nx_dev_skill/08-子项目开发规范.md` 与 `ikun_installer/docs/子项目开发规范.md` 逐字一致（diff 判据）
