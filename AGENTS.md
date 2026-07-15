# AGENTS.md — VPS 部署操作契约

本文件是自动化代理的最高优先级仓库内指令。目标是安全、可复现地部署
`mack-a/v2ray-agent`，并交付一个不依赖旧代理服务器的独立 VPS 配置。

## 1. 权限和停止点

可以自主执行：

- 读取服务器、DNS、Cloudflare 和客户端当前状态；
- 安装正常所需的软件包、Xray、Nginx 和上游脚本；
- 创建配置备份、临时验证文件和可回滚配置；
- 修改本次明确指定的服务器、域名记录和精确范围的 Cloudflare 规则；
- 运行网络、TLS、订阅、节点和重启验证。

必须暂停并让用户确认：

- 未给出域名时，在创建或修改 Cloudflare DNS 记录之前；
- 需要删除旧节点、旧 DNS、旧 WAF 规则或旧服务器时；
- 需要扩大为区域级 WAF 放行、关闭整体安全功能或使用 `Flexible` TLS 时；
- 发现服务器上有不属于本次部署的现有生产服务且端口或 Nginx 配置会冲突时；
- SSH 主机指纹异常变化、权限不足或备份失败时。

绝对禁止：

- 切换操作者电脑上的 Clash 节点、系统代理、TUN 或默认路由；
- 将私钥、密码、Cloudflare Token、订阅 Token、UUID、真实 IP 或账号信息写入仓库；
- 为了“先通再说”而关闭整个 Cloudflare WAF、关闭 TLS 校验或放行全部 URL；
- 未备份就覆盖 Xray、Nginx、防火墙或证书配置；
- 在验证新线路独立可用前删除旧线路；
- 把“命令执行成功”当作“部署完成”。

## 2. 最小输入

开始前确认以下输入，仅保存在本机临时环境或安全凭据系统中：

- `SERVER_HOST`、`SERVER_USER`、SSH 私钥或等价登录方式；
- `DOMAIN`（若缺失，按停止点规则等待用户选择）；
- Cloudflare 已登录会话，或只包含 DNS/WAF/SSL 所需权限的 API Token；
- 用户是否接受推荐架构：Reality 直连为主，WS/TLS 443 经 Cloudflare 为备用；
- 服务器上是否有必须保留的站点或服务。

不要要求用户把秘密提交到 Git。不要在终端回显完整 Token。

## 3. 执行状态机

严格按以下状态推进；每个状态都要留下简短证据。失败时停在当前状态并诊断，不跳过门禁。

```text
INPUTS
  -> CONTROL_PATH_SAFE
  -> SERVER_PREFLIGHTED
  -> BACKUP_CREATED
  -> UPSTREAM_REVIEWED
  -> CORE_INSTALLED
  -> ORIGIN_VALIDATED
  -> DOMAIN_CONFIRMED        [可能需要用户]
  -> CLOUDFLARE_CONFIGURED
  -> SUBSCRIPTIONS_VALIDATED
  -> NODES_VALIDATED
  -> CLIENT_HANDOFF          [用户执行最终切换]
  -> REBOOT_VALIDATED
  -> COMPLETE
```

### CONTROL_PATH_SAFE

- 记录当前电脑的已知可用代理，但不改变它。
- 若当前远程控制依赖代理，所有服务器和 Cloudflare 操作都在旧线路上完成。
- 准备断线恢复方式：云厂商 Console、SSH 重新连接命令、配置备份位置。

### SERVER_PREFLIGHTED

- 验证系统、架构、root/sudo、时间同步、磁盘、内存、IPv4、IPv6、DNS、80/443 和计划端口。
- 检查现有监听、Nginx/Apache/Caddy、Xray/sing-box、UFW/nftables/iptables。
- 从服务器分别测试 IPv4/IPv6 外网；IPv6 不完整时明确禁用或不发布 AAAA。
- 运行 `scripts/preflight-server.sh`，保存去敏结果。

### BACKUP_CREATED

- 备份 `/etc/nginx`、Xray/sing-box 配置、防火墙规则、证书配置和现有脚本目录。
- 备份目录带 UTC 时间戳；验证能读取；记录精确回滚命令。

### UPSTREAM_REVIEWED

- 打开上游当前 README、release 和安装脚本。
- 使用 HTTPS 且启用证书校验下载到本地文件；记录 SHA-256；先检查再执行。
- 不默认复用文档中的旧菜单编号、端口或路径。
- 若上游命令使用 `--no-check-certificate`，不要机械照搬；优先正常验证 HTTPS。

### CORE_INSTALLED

推荐最小节点集：

1. VLESS Reality Vision：主线路，独立端口，直连源站；
2. VLESS WS/TLS：备用线路，经域名 443 和 Cloudflare；
3. 可选 VMess WS/TLS：只在客户端兼容性确有需要时增加。

不要为了数量一次打开所有协议。每增加一种协议，就增加一个证书、端口、路由或客户端兼容性故障面。

### ORIGIN_VALIDATED

在接触 Cloudflare 前，从源站本机和外部各验证：

- 服务进程 active，端口监听与设计一致；
- `nginx -t` 成功；证书 SAN 包含域名且未过期；
- 使用 `curl --resolve` 直连源站时，443 TLS 和订阅路径返回预期内容；
- Reality 端口可达，配置中的 serverName/publicKey/shortId 与导出节点一致；
- 重启单个服务后能恢复。

### DOMAIN_CONFIRMED / CLOUDFLARE_CONFIGURED

- A 指向服务器 IPv4；除非已验证，不创建 AAAA。
- Reality 使用 DNS only 的专用主机名或直接 IP；WS/TLS/订阅域名可用 Proxied。
- SSL/TLS 模式使用 `Full (strict)`。
- 若订阅被 Challenge，只为精确主机 + 两个精确随机路径建立 Skip 规则。
- 不创建 `starts_with('/s/')` 之类的宽泛放行。

### SUBSCRIPTIONS_VALIDATED

必须从服务器外部、无浏览器 Cookie 的客户端验证：

- 完整 Clash profile 返回 200，Content-Type/正文是 YAML，不是 HTML；
- provider 返回 200，包含期望节点名称；
- 响应头没有 `Cf-Mitigated: challenge`；
- 错误响应和日志不泄露 Token。

### NODES_VALIDATED

保持本机当前线路不变，用独立测试客户端、临时容器或第二台设备验证：

- Reality 主节点完成握手、DNS 和 HTTPS 请求；
- WS/TLS 备用节点完成握手、DNS 和 HTTPS 请求；
- 出口 IPv4 显示目标 VPS 的地区和 ASN；
- IPv6 若禁用，客户端不会从本地 IPv6/QUIC 绕过代理；
- 不存在对旧服务器的 relay、proxy-provider 或链式依赖。

### CLIENT_HANDOFF / REBOOT_VALIDATED

- 把订阅 URL 交给用户；用户自己导入并切换。
- 代理必须含明确的 `ipv6: false`（除非 IPv6 已验证）。
- 用户确认网页、DNS、GitHub/Google/YouTube 等基础站点和 IP 地区。
- VPS 完整重启后重新执行端点、服务、节点和出口验证。
- 最后才允许清理旧线路，而且仍需用户明确同意。

## 4. 失败处理

按 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) 的层级定位。不要连续随机改配置。

每次变更遵循：

1. 写下当前可观察症状；
2. 提出一个可证伪假设；
3. 做一个最小变更；
4. 重跑同一个验证；
5. 成功则记录，失败则回滚。

SSH 或远程控制中断时，优先恢复控制通道，不继续修改网络。

## 5. 最终交付格式

最终报告必须包含：

- 已完成的架构和节点类型，不包含秘密；
- DNS、TLS、WAF、订阅、握手、出口、重启各自的验证结果；
- 用户需要保存的秘密所在位置（只写位置，不写内容）；
- 备份和回滚位置；
- 仍存在的风险或未验证项；
- 明确说明本机代理是否由用户亲自切换；
- 明确说明新配置是否完全不依赖旧服务器。

若任何完成定义未满足，报告状态为“部分完成”，不能写“已完成”。
