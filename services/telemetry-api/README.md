# 爱坤工具箱遥测服务

遥测服务接收安装器的更新事件和受管设备快照。安装器只有在管理员配置一次性注册码后才启用后台发送；没有注册码时完全不发送，不影响安装、更新或插件运行。

## 生产入口

- HTTPS：`https://tm.h.zss.fan:2233`
- 内网后端：`http://10.0.0.8:5080`
- 存活检查：`GET /health/live`
- 就绪检查：`GET /health/ready`（不应公开给普通用户）

Lucky 代理仅转发 `/v1/register`、`/v1/events` 和 `/v1/device-snapshot`，并设置 `X-Forwarded-Proto`、`X-Forwarded-For` 和目标 Host。

## 客户端配置

受管环境通过注册表 `HKCU\Software\ikun_tools` 配置：

- `telemetry_enrollment_code`：管理员通过 CLI 生成的一次性注册码；使用后服务端立即作废。
- `telemetry_url`：可选，默认 `https://tm.h.zss.fan:2233`。

也可使用环境变量 `IKUN_TELEMETRY_ENROLLMENT_CODE`、`IKUN_TELEMETRY_URL`。设备 token 由 Windows DPAPI CurrentUser 加密后保存，服务端只保存 SHA-256，不保存明文 token。

## 管理 CLI

管理连接串只通过环境变量 `IKUN_TELEMETRY_ADMIN_DB` 注入，必须使用迁移管理员身份，不能使用 API 运行账号：

```powershell
$env:IKUN_TELEMETRY_ADMIN_DB = 'Host=10.0.0.8;Port=5432;Database=ikun_telemetry;Username=ikun_telemetry_migrator;Password=...'
dotnet run --project admin/Ikun.Telemetry.Admin.csproj -- create-code 24
dotnet run --project admin/Ikun.Telemetry.Admin.csproj -- list-devices
dotnet run --project admin/Ikun.Telemetry.Admin.csproj -- disable-device <install_id>
```

CLI 不会打印数据库密码；注册码只在标准输出显示一次，交付后不得写入 Git、日志或安装器二进制。

## 数据与隐私边界

设备快照包含计算机名、Windows 用户名和 MAC 地址。服务端使用 AES-256-GCM 加密原文，并以 HMAC 保存检索值；事件表不保存原始 IP。该功能属于受管设备策略，部署方应在组织内部告知用途、保留期限和访问范围；安装界面不提供伪装式隐私勾选框，也不绕过组织政策。

## 部署与验证

```bash
docker build -t ikun-telemetry:latest .
docker run --name ikun-telemetry --env-file /etc/ikun-telemetry/telemetry.env \
  -p 10.0.0.8:5080:5080 --restart unless-stopped ikun-telemetry:latest
```

迁移必须由独立迁移账号执行；运行账号只拥有 `SELECT/INSERT/UPDATE` 和序列使用权，禁止 DDL、DELETE、TRUNCATE。真实部署还应限制 PostgreSQL 5432 的网络来源并定期执行 90 天事件/30 天安全记录清理。

## 测试

```bash
dotnet test tests/Ikun.Telemetry.Tests/Ikun.Telemetry.Tests.csproj
dotnet build admin/Ikun.Telemetry.Admin.csproj -c Release
```

当前客户端发送均为后台 best-effort，单次超时 3 秒，失败不阻塞主流程。
