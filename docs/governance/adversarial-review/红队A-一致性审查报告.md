# 红队 A 审查报告（一致性/逻辑攻击）

> 攻击角度：一致性与规则正确性。核验方式：只读比对规范草案与 `repos/` 本地克隆实况。GBK 文件用 Encoding 936 解码，PE 导出用 mingw `objdump -p` 逐表核验。
> 时间：2026-08。对象：ikun-整体开发规范-v0.1.md。

## P0 发现

### P0-1 菜单 LABEL 是「第三套中文名」，SSOT 矩阵与 G5 均未覆盖，§4.4 废除 08 附录后它失去唯一权威源
- 证据：菜单 LABEL 既不等于 plugin.meta 的 name_cn 也不等于 icon_cn，而是 7/7 全部对不上的第三套名字。示例 ejector_layout：custom.men LABEL=顶针布局；meta name_cn=顶针快速布局、icon_cn=顶针；08 附录「中文全称」=顶针布局（正好等于菜单 LABEL）。其余 6 个在册插件同样成立。
- 攻击：§4.1 声称菜单 LABEL 是 meta 的派生且由 G5 校验，但 G5 判据只是「引用都存在」，从不比对 LABEL 文本；菜单 LABEL 的当前事实权威源其实是 08 附录表，而 §4.4 又要废除它。
- 处置：G5 增加「菜单 LABEL == plugin.meta.name_cn 字节比较」；§8.2 明确 LABEL 逐字等于 name_cn；对齐任务列为 M8b。

### P0-2 镜像链方向自相矛盾（同日同步、禁止反向修改 vs M8 排最后、08 仍自称权威）
- 证据：nx_dev_skill/08 头部「都以本文为准」、含「4 汉字」旧规则与 9 插件附录表；ikun_installer/docs 声明「权威源在 nx_dev_skill」；而 L3 已修订 08 内容却把镜像同步推迟到 M8（最后）。
- 处置：§2.2 增加过渡条款（L3 生效日起冲突以 L3 为准、新修订只改 L3）；M8 拆分为 M8a（镜像定型，与 v1.0 生效同一步完成，P0）/M8b（LABEL 对齐，G5 上线后，P1）。

### P0-3 「三份文件 diff 一致」是不可判定的机器判据
- 证据：L3（整体规范）与 08/docs（子集镜像）范围根本不同，不可能与整份 L3 diff 一致。
- 处置：判据改为「08 与 docs 两镜像逐字一致 + 头部声明指向 L3」。

### P0-4 附录 A 与 §0 盘点多处事实错误
- 证据：CHANGELOG 缺少数「8 个」实为 9、「含 4 个已并入」实为 5；MultiEntityNester「无版本段」实有 v1.0.0；plate_dwg_export「缺 .gitattributes」实有；smart_ejector_heater 与 riser_base_fillet「缺 build.ps1」实有；plugin.meta「9 份」实为 10 份。
- 处置：全部勘误；附录 A 改为由 verify-repo.ps1 扫描生成（registry.json），禁止手工维护。

## P1 发现（处置均并入规范）
- P1-1 G5 只判单方向（plugins.json ⊆ meta 方向），漏「in_ikun=true 未登记」逃逸；且未定义数据来源与「在册 dll 集合」口径 → G5 改双向 + registry.json 分工 + 口径明确（application/ 实际 dll 基名）+ 每仓 dll 基名唯一。
- P1-2 G7「无 U+FFFD」判据不充分：UTF-8 中文字节被当 GBK 解码往往得到合法 GBK 字符（鐖卞潳）而不产生 U+FFFD → G7 增加「字节往返一致 + 与 G5 的 LABEL==name_cn 文本比对联动」。
- P1-3 M4 架构不可行：assemble.sh 的临时 clone 目录被 trap 删除，gen-icons.sh 拿不到 plugin.meta → M4 增加「assemble.sh 落地导出 ci/_plugin_meta.tsv 供 gen-icons 消费」。
- P1-4 M6 范围漏 UpdateManager.cs 的 DefaultProxy/GiteaLatestApi → §11.4 扩为 6 处（含 DeploymentLayout.cs:62）。
- P1-5 G4「给该仓开 Issue」与 CI token 最小权限矛盾 → Issue 一律开在 ikun_installer 仓并标注插件名。
- P1-6 M5 后本地 dotnet publish 直接跑会产空包 → M5 保留空目录 + .gitkeep，README 注明出包必须 dev-assemble。
- P1-7 §6.6「W 可省」与版本单调冲突 → Release name 固定四段、W 不可省。
- P1-8 图标文件名 SSOT 未落实（ikun_ejector.bmp vs ikun_ejector_layout.bmp 并存）→ G5 增加「BITMAP 文件名 == ikun_<英文名>.bmp、无孤儿/重复 bmp」，M4 归一。
- P1-9 「禁止 force push」无机器执法、提交无签名规则 → §12.1 增加提交签名渐进目标；M12 升 P0（当日完成）。

## P2 建议（处置并入规范）
- G3 工具不在 dotnet/sdk:9.0 base image → M7b 须安装固定版本工具（已核验现存 17 个 dll 全部真实导出 ufusr/ufusr_ask_unload，G3 对存量成立）。
- GBK 菜单文件未被 .gitattributes 保护 → M2 增加 .men/.rtb/.tbr 标 binary。
- 插件 .gitignore 覆盖不全、模板 build.ps1 不清 .obj（runner_section_area 正是这样入库的）→ M2 对齐 §7.4 清单 + 模板补清理。
- ikun_updater 是第 12 个插件式组件却无 CHANGELOG/版本/清册 → 附录 A 定位为「安装器组件」，制品规则同插件（G8 纳入），变更记入安装器 CHANGELOG。
- M1 期间双 dll 入库风险 → M1 阶段 1 产出新名 dll 时同提交删旧名制品；G5 兜底。
- ParseRemoteVersion 正则未锚定 → M9 补锚点用例。
- ikun_installer/CLAUDE.md 引用 docs/dev-standards.md 等 5 份悬空文档 → M2 修复。

## 一句话总评
草案的「单一可信源」与「机器可判闸门」两大支柱在落地处都断了：菜单 LABEL 是规范没定义的第三套中文名、镜像链的权威方向与迁移顺序自相矛盾、附录清册有多处事实错误，且 G5 只查单方向、G7 判据躲不过「存成 UTF-8」这个它自己点名要防的事故。
