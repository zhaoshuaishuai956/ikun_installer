# 红队 B 审查报告（安全与信任链攻击）

> 攻击角度：安全与信任链。审查对象：ikun-整体开发规范-v0.1.md + repos/ 本地克隆实况。行号以核验时文件为准。
> 时间：2026-08。

## P0 安全发现

### P0-1 恶意 dll 可零闸门直通用户 NX 进程（G1–G7 对「恶意内容」全部失明）
- 攻击路径：插件作者（或任一插件仓写权限者）把恶意 dll 提交 master → notify-installer.yml 自动触发打包 → assemble.sh clone 收集 → 编译进单文件 exe 上传 latest → 用户下载 → ExtractResources 释放 → NX 加载执行（DllMain/ufusr）。
- G1–G7 全是元数据/命名/编码检查；G2 只查 XML 良构；G3 只查导出表（恶意载荷放 DllMain 即可，本仓 ikun_updater.cpp 的 DllMain CreateThread 即合法模式示范）。
- 处置：§7.3 增加边界声明（G 系闸门不做行为判定）；§12.3 制品变更强制 PR + D 类审查；新增 G8 源码-制品绑定（dll 内嵌构建 SHA，CI 提取比对，M14）；M13 代码签名（P0）。

### P0-2 INSTALLER_DISPATCH_TOKEN 实为「全库读 + 安装器写」的万能 PAT，7 份复制 + curl -k
- 证据：notify-installer.yml:17 用 curl -k 发送 token（MITM 可窃）；同一 token 在 pack.yml 当 PAT 注入：clone 全部私有仓（assemble.sh:72-73）、删除 release/tag、创建 release、上传资产（publish-release.sh:65-83）。泄露爆炸半径 = 直接覆盖 latest 资产 = 全员被推送任意 exe。
- 处置：§11.2 重写为如实描述 + 拆分双 token（dispatch-only / release-only）+ 轮换 + CI scope 自测告警 + notify 模板去 -k；M11 升 P1。

### P0-3 更新链信任边界 = TLS + FileVersion，无签名强制、无 sha256、降级可伪造 → 任意 exe 以管理员运行
- 攻击层次：① name/FileVersion/资产全由攻击者控制，可命名 v9.9.9.999 通过降级拒绝；② VerifyAuthenticode 把 NotSigned 映射为 false，但 VerifyDownloadedInstaller 返回「无签名也放行」（sig != null 逻辑）；③ LaunchInstaller 用 runas 以管理员启动下载 exe。系统证书依赖带外 CA 分发（规范从未定义），无证书固定。本地提权：%TEMP% 共享目录 TOCTOU 换文件 + 弱校验 → 低权限用户可提权。
- 处置：新增 M13（P0）Authenticode 签名 + fail-closed + 原子切换；M10 升 P1 并声明同信道局限；§9.3 重写（%LOCALAPPDATA%、独占句柄收敛 TOCTOU、自签 CA 带外分发 + 安装器可见提示）；§11.7 安装器危险操作红线。

### P0-4 icon_cn（外部输入）直通 ImageMagick -annotate：@file 读文件/% 转义 → 凭证外泄进公开图标
- 攻击路径：M4 把图标文字来源改为插件仓 plugin.meta 的 icon_cn（完全外部输入）→ gen-icons.sh:46-49 原样传给 convert -annotate → @ 开头被当文件名读取内容（@/proc/self/environ 可把 PAT 渲染进 BMP 公开下载），% 触发格式转义（CVE-2016-3714 同类）。
- 处置：§11.3 增加 plugin.meta 字段白名单（icon_cn 纯汉字 1-2 字、name_cn 白名单、category 枚举）；gen-icons.sh 前置校验 + -limit；M4 落地必须同步该 gate。

## P1 安全发现（处置均并入规范）
- P1-1 G7 只查编码可逆不查 NX 菜单结构 → G7 增加结构校验（块配对/ACTIONS 目标/VERSION 合法性）。
- P1-2 SSOT 把菜单 LABEL 定为 meta 派生但无生成器/消毒规则 → §11.3 增加 LABEL 生成转义规则。
- P1-3 custom_dirs.dat 按 UTF-8 读写破坏用户 GBK 中文路径 → C1 补编码探测约定。
- P1-4 新代码仍硬编码路径/URL/默认代理（UpdateManager.cs:22-23、Form1.cs:31、ikun_updater.cpp:28）→ §11.4 扩为 6 处、M6 覆盖。
- P1-5 §11.1「Token 不得写入文件」无机器执法 → G6 增加 secret 扫描；M12 升 P1。
- P1-6 缺「安装器自身危险操作」红线（部署槽实现本身合格：CreateUniqueRoot 字符白名单中和了路径穿越）→ §11.7。
- P1-7 §11 逐条可执行性评估表（§11.2 与实况矛盾已重写等）。

## P2 加固建议（处置并入规范）
- ParseRemoteVersion/JSON 正则脆弱 → M9（锚点、≤4 段、强类型解析）。
- 运行时 apt-get install imagemagick 未锁定版本 → M4 固定版本。
- nx_dev_skill 的 sslVerify=false 模式外溢 → §11.6 证书策略（降级为一次性诊断）。
- Release 正文 repo 名未消毒 → §11.3 白名单 ^[a-z0-9_]+$。
- M9 测试盲区（无签名 exe 处置断言）→ 并入 M9/M13。

## 一句话总评
规范把安全闸门几乎全押在「元数据/命名/编码」层面，对「提交二进制里跑什么代码」和「谁拿着能覆盖 latest 的 token」这两条真正的信任链没有闸门、没有代码签名、且 §11.2 的凭证最小化陈述与实况相反——建议先把 P0-1/P0-2/P0-3/P0-4 闭环、把 M10/M11/M12 提级，再谈 v1.0。
