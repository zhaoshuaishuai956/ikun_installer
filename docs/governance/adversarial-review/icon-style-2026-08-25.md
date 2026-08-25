# 菜单图标规范与统一重绘对抗审查（2026-08-25）

范围：权威规范新增图标格式/视觉规则、一致性脚本新增 BMP 头校验，以及七个在册业务插件的菜单图标重绘。

## P0

无。未改写 plugins.json、GBK 菜单、Ribbon BUTTON、LABEL、ACTIONS 或 custom_dirs.dat，因此不会使既有注册按钮失效。

## P1（已修复）

1. 反例：图标文件存在但为错误格式或尺寸，NX 可能显示失败或出现不一致缩放。
   - 修复：check_consistency.py 校验 BMP 签名、24×24 尺寸和 24 位色深；菜单文件名仍按 repo 推导。

2. 反例：新增图标与既有图标规格漂移，CI 只检查文件存在，无法阻止不兼容资源进入 Release。
   - 修复：权威规范 §4.1 固化文件格式与视觉构图规则；七个业务图标已按同一规格重绘。

## P2（未验证边界）

1. 已完成原尺寸 24 像素视觉检查，但未在 NX Ribbon 实机截图验证各 DPI 缩放效果。
2. 图标以生成式源图裁切而成；格式和命名可机器验证，审美一致性仍需后续人工评审。

## 证据

- python ci/check_consistency.py：应同时覆盖菜单 GBK 往返、资源集合及新增 BMP 格式闸门。
- dotnet run --project tests/DeploymentLayoutTests.csproj -c Release --no-restore：覆盖原子覆盖、文件占用保旧和部署目录恢复。
