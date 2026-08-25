# 遥测管理 CLI

该工具只允许管理员在受控主机上运行。不要把 `IKUN_TELEMETRY_ADMIN_DB` 写入脚本、仓库或 CI 日志。

命令：

- `create-code [hours]`：生成一次性注册码，默认 24 小时，范围 1–720 小时。
- `list-devices`：列出设备安装 ID、创建时间和停用状态。
- `disable-device <install_id>`：停用设备 token。

运行账号不能使用此工具；迁移管理员账号应设置为 `NOLOGIN`，需要运行 CLI 时由受控管理员临时启用。
