# 对抗性审查报告（服务端当前版本）

## 范围

只审查 API、迁移、运行模板；不审查或修改客户端、NX 插件、更新/下载逻辑、Lucky 实际规则和真实 PostgreSQL。

## 当前证据

- 构建/测试环境：ARM64 Docker `mcr.microsoft.com/dotnet/sdk:9.0`
- 测试结果：7 passed, 0 failed
- 主机没有 .NET SDK
- 未连接真实 PostgreSQL
- 未部署 API
- 未修改 Lucky
- 未开放 5080/公网
- 未接入真实设备

## P0

### P0-1 生产部署未完成

- 复现：当前没有目标域名、Lucky 精确源 IP、运行环境和 migration 账户。
- 证据：仅有本地暂存源码，README 明确未部署。
- 修复：部署前完成 PostgreSQL 迁移、runtime 权限、Lucky 备份/规则、HTTPS 和防火墙测试。
- 回归：待目标设备提供后执行。

### P0-2 管理 CLI 尚未实现

- 影响：无法安全生成 enrollment code、禁用设备、查询设备和轮换 token。
- 处理：禁止公网启用；补充本地 CLI 后再注册设备。

## P1

### P1-1 KnownProxies/真实代理 IP尚未配置

- 影响：代码当前不信任代理头，且没有真实拓扑信息。
- 修复：目标 Lucky IP 确认后，在应用层配置精确代理信任和转发头处理；非可信来源忽略转发头。

### P1-2 PostgreSQL 集成/权限负测试未完成

- 影响：SQL 已参数化并使用幂等写入，但没有真实数据库证据。
- 修复：使用迁移角色执行 SQL；使用 runtime 账号验证 CREATE/ALTER/DROP/DELETE/TRUNCATE 和 Gitea 访问均失败。

### P1-3 全局并发/速率限制需要生产负载测试

- 代码具备全局并发 50、全局 200/s、IP/令牌计数器；尚未进行真实压力测试和多 NAT 误伤率测试。
- 修复：执行 429、慢请求、连接池耗尽和随机分区内存测试。

### P1-4 device snapshot 加密存储需要真实数据库验收

- 使用 AES-256-GCM、每条数据独立 12-byte nonce、固定 AAD `ikun-telemetry-v1`、HMAC-SHA256 检索值。
- 尚未证明备份、查询工具和恢复流程不会输出明文。

## P2

- 需要结构化隐私安全日志和 request_id。
- 需要 30/90 天清理任务。
- 需要真实管理 CLI 审计日志。
- 需要容量基线、恢复演练和密钥轮换流程。

## 已检查的攻击面

| 场景 | 当前状态 |
|---|---|
| 超大请求 | Kestrel 8KB + register 4KB 检查 |
| 未知 JSON 字段 | `UnmappedMemberHandling.Disallow` |
| 重复 event_id | PostgreSQL 主键/ON CONFLICT |
| 重复 snapshot_id | PostgreSQL 主键/ON CONFLICT |
| 随机 install_id 分区 | token 验证后才创建 token 分区 |
| token 固定时间比较 | SHA-256 后固定时间比较 |
| 非法 MAC | 格式、全零、广播、数量、去重校验 |
| 原始设备信息日志 | 当前 API 不主动记录正文；部署日志策略仍待补充 |
| SQL 注入 | Npgsql 参数化 |
| PostgreSQL 错误泄露 | 全局异常处理统一 503 |
| 公网管理接口 | 未实现/未部署 |
| Swagger | 未配置 |
| 5080 直接公网 | API 只监听 localhost |
| 5432 公网 | 本次未修改主机 PostgreSQL 暴露；部署前必须收紧 |
| Lucky 绕过 | 未配置 Lucky；必须目标设备上实测 |

## 结论

当前源码测试通过，但不能宣称“已部署”或“已通过生产 P0/P1”。在管理 CLI、真实 PostgreSQL 权限测试、KnownProxies、Lucky HTTPS、端口边界和负载测试完成前，不得开放公网或交给客户端接入。

## 回滚

本次没有运行时变更。回滚为删除暂存目录或回到 `codex/telemetry-api` 分支提交前状态；后续部署必须先备份 Lucky 和数据库。
