# 红队 C 审查报告（落地可行性与边界覆盖）

> 攻击者身份：照规范老实干活的单人开发者 + 能力一般的 AI 代理（查表照做）。模拟第 1/30/90 天真实执行。证据均取自 repos/ 本地克隆与规范草案。
> 时间：2026-08。

## P0 落地阻断

### P0-1 「生效日」与过渡期未定义，第一天规则一半无牙齿、一半咬人
- 第 1 天走查（修 ejector_layout 一个 bug 并发布）：旧流程可过；新增硬步骤里唯一有牙齿的是 CHANGELOG（release-notes.sh 是活代码）；G1–G7/PR/红队全是无执行者的死条文（实现是 M7）。真正的「卡死」推迟到 M7 落地那周爆发（积压债一次性打红）。
- 处置：新增 §0.1 生效日与过渡期（M12 当日、M7a 当周、M7b 落地前不阻断）。

### P0-2 「本规范所在仓」不存在，登记/PR/镜像链无处落地
- 处置：§2.2 增加存放点规则（ikun_dev_standard 或 ikun_installer/docs，维护者二选一登记）；附录 A 增行。

### P0-3 附录 A「唯一登记处」在 v0.1 即与实况漂移，M2 含幽灵工
- 实证：smart_ejector_heater 与 riser_base_fillet **有** build.ps1（附录 A 称缺）；plate_dwg_export **有** .gitattributes（附录 A 称缺）。
- 处置：附录 A 全部勘误；M2 第一步改「脚本扫描生成真值表」；附录 A 改为机器生成（registry.json）。

### P0-4 single_line_text 的 slfont.dat 源不可重建，P3/V3 对 dat 恒不成立
- 证据：.gitignore 排除 data/graphics.txt（Make Me a Hanzi 汉字源），build_font.py 硬性依赖 → 全新 clone 不可重建 slfont.dat。
- 处置：C7 登记为「不可重建遗留资产，仅限存量、禁止再改」。

### P0-5 M1 改名清单漏项，会打断 sibling 工具与安装器
- 证据：single_line_text/tools/gen_dlx.py:12 写死 ../MultiEntityNester/MultiEntityNester.dlx；M1「中心侧改引用」漏 build.ps1 $subIcon、tests/Program.cs 3 处字面量、DeployResources 二进制、menu BITMAP。
- 处置：M1 影响面按 grep -rl 全仓展开；gen_dlx.py 跨仓依赖改自包含；阶段 1 顺带仓库卫生（.dlx.bak/artifacts/多余 build 脚本）。

### P0-6 豁免登记机制无执行者，且「唯一豁免」本身未登记
- 证据：nx_dev_skill/README.md 无任何「规范豁免」小节；runner_section_area 既不在附录 A 又被 M2 要求清理+登记（循环）。
- 处置：§2.3 豁免改为机器可判字段（README `## 规范豁免` 标题 + 一行理由，verify-repo.ps1 检查）；runner_section_area 30 天死线。

## P1 高成本或易腐化条款（处置均并入规范）
- P1-1 八文件强制对 in_ikun=false 与未登记仓是纯负担（CHANGELOG 无消费者）→ §5 分级：并入仓标红、未并入仓标黄；安全规则不分级。
- P1-2 §13 成本曲线与「自审表演」退化 → A 类限语义级修订；D 类机器 checklist 替代人工红队（首次接入保留人工）；C 类删滚动抽查改 pack 失败自动归因。
- P1-3 机器判据真伪（G5 名不符实、§6.3「看得懂」无判据、§10.4「已测试」可伪造）→ G5 补 LABEL==name_cn 字节比较；§10.4 诚实降级为审查参考材料；Unreleased 加 20 条上限机器规则。
- P1-4 G4 阶段一几乎免费却和 G3/G5/G7 一起压进 M7 → 拆 M7a（当周上线，P0）/M7b。
- P1-5 DeploymentLayoutTests 未进 CI、DeploymentLayout.cs:62 硬编码 → M9 纯逻辑化进 CI；M6 第六处。

## 规则可绕过性（5 条，处置均并入规范）
1. CHANGELOG 空话合规 → §6.3 质量抽查（M2 回填适用）。
2. Unreleased 永不折叠 → §6.2 上限 20 条机器规则。
3. 「已测试」伪造 → §10.4 效力边界声明。
4. 改源码不重编 → 静默不发布 → M14 check-sync 工作流（push 含源码扩展名时比对内嵌 SHA 与 HEAD，不等开 Issue）。
5. legacy update.ps1/NAS 通道绕过全部闸门 → M6 改为「从仓库删除」（不保留可执行副本）。

## 迁移清单工作量与顺序修正
- M1 最大最险（≥20 文件、8–12 提交、3–5h + 全量 NX 复验）；P0 定性存疑（外观债）→ 降 P1。
- M12 是 Gitea UI 一个开关（5 分钟）→ 升 P0/当日。
- 顺序修正：闸门先于高危改名（M1 阶段 2/3 仅在 G5 可用后）；M7a/M12 提最前。

## 一句话总评
这份规范的问题不是「太严」，而是「牙齿的落地顺序与宣称的权威性错位」——把真正机器可判、今天就能零成本上线的闸门（G4）埋进了最重的 M7，把只能人工判断的软条款标榜成机器契约，把「唯一登记处」在 v0.1 就写漂移，把 4 个边界对象（dat 不可重建、未登记仓循环定义、未并入仓纯负担、main 豁免未登记）留成了无人接的盲区。
