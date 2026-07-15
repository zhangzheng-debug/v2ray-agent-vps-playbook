# End-to-End Runbook

这份流程假设服务器是受支持的 Linux VPS，用户有 root/sudo 权限，并希望使用
`mack-a/v2ray-agent` 管理 Xray。命令和菜单会随上游变化；每次部署必须重新查看上游。

## Phase 0 — 输入、授权和安全通道

1. 复制 `templates/deployment.env.example` 为仓库外部的临时 `deployment.env`。
2. 收集 SSH、域名和 Cloudflare 权限，但不要把秘密粘贴到 Git tracked 文件。
3. 记录当前已知可用网络路径；如果 Codex 正在远程操作电脑，不触碰 Clash/TUN/系统代理。
4. 确认云厂商 Web Console 可用，避免防火墙或 SSH 变更后完全失联。
5. 取得当前 SSH 主机指纹并与云厂商控制台核对。

门禁：能从已知安全通道登录服务器，且有断线恢复方式。

## Phase 1 — 只读服务器预检

把 `scripts/preflight-server.sh` 临时复制到服务器并以 root 运行。它不会修改系统。

额外检查：

```bash
ss -lntup
systemctl --no-pager --type=service --state=running
nginx -T 2>/dev/null | sed -n '1,160p'
```

确认：

- Debian/Ubuntu 等上游支持的系统和 CPU 架构；
- 时间同步正常，证书依赖正确时间；
- 80/443 和 Reality 计划端口未被未知服务占用；
- 云厂商防火墙、UFW/nftables/iptables 三层规则不冲突；
- IPv4 出口正常；IPv6 要么完整正常，要么不发布。

门禁：端口、现有服务和网络策略已理解，没有未处理的生产冲突。

## Phase 2 — 备份与回滚

在 VPS 创建 UTC 时间戳备份目录，例如 `/root/vps-playbook-backup-YYYYMMDDTHHMMSSZ`，备份：

- `/etc/nginx`；
- Xray/sing-box 配置和 systemd unit；
- 现有 `v2ray-agent` 目录；
- ACME/证书目录和续期配置；
- `nft list ruleset`、`iptables-save`、UFW 状态；
- `ss -lntup` 和相关服务状态。

验证备份文件不是空文件，并写下回滚步骤。不要把含密钥的备份下载进本仓库。

门禁：备份可读，回滚命令已准备，云厂商 Console 可用。

## Phase 3 — 核对并运行上游脚本

打开：

- <https://github.com/mack-a/v2ray-agent>
- 当前 `README.md`、最新 release、`install.sh` 的 raw 内容。

推荐流程是先下载、记录哈希、检查，再执行，而不是把远程内容直接 pipe 给 shell：

```bash
curl -fL --proto '=https' --tlsv1.2 \
  -o /root/install.sh \
  https://raw.githubusercontent.com/mack-a/v2ray-agent/master/install.sh
sha256sum /root/install.sh
less /root/install.sh
chmod 700 /root/install.sh
/root/install.sh
```

上游当前管理命令通常为 `vasma`，但必须以当时 README 为准。记录上游 commit/release 和脚本哈希。

门禁：脚本来源、版本、哈希和关键操作已检查，安装没有覆盖必须保留的服务。

## Phase 4 — 最小协议集

### 4.1 Reality 主线路

安装 VLESS Reality Vision：

- 使用随机高位端口，云防火墙和主机防火墙仅开放必要 TCP；
- 保存 server、port、UUID、public key、shortId、serverName、flow；
- private key 只留在 VPS；
- 该连接直达源站，不经过 Cloudflare 橙云。

若安装 VLESS Reality XHTTP，也默认使用源站 IP 或 DNS only 的直连主机。上游界面即使写着
“CDN 推荐”，也不能据此假定普通 Cloudflare 橙云支持该协议和随机高端口；以最终握手测试为准。

### 4.2 WS/TLS 443 备用线路

安装 VLESS WS/TLS：

- 外部入口固定为域名 `443`；
- Nginx 终止 TLS，再按精确 WebSocket path 转发到本地 Xray 端口；
- WebSocket path 使用高熵随机值；
- 源站证书包含该域名，Cloudflare 设置 Full (strict)。

可选 VMess WS/TLS 仅用于旧客户端兼容，安装后必须单独验证。

门禁：Xray 配置检查通过、服务 active、监听端口符合设计。

## Phase 5 — Nginx、证书和源站验证

1. 申请或安装域名证书；证书私钥权限仅 root 可读。
2. 增加 WS 路由和两个精确订阅路由。参考
   `templates/nginx-subscription-locations.conf.example`，按上游实际订阅后端修改。
3. 执行 `nginx -t`，只在成功后 reload。
4. 在源站本机测试：

```bash
curl -fsS --resolve '<DOMAIN>:443:127.0.0.1' \
  'https://<DOMAIN>/s/clashMetaProfiles/<TOKEN>' -o /dev/null
openssl s_client -connect 127.0.0.1:443 -servername '<DOMAIN>' </dev/null
```

5. 从外部绕过 Cloudflare、直连源站测试：

```bash
curl -fsS --resolve '<DOMAIN>:443:<SERVER_IPV4>' \
  'https://<DOMAIN>/s/clashMetaProfiles/<TOKEN>' -o /dev/null
```

如果源站失败，不要先改 Cloudflare。

门禁：本机和外部 `--resolve` 均成功，证书 SAN、有效期、Nginx 和订阅正文正确。

## Phase 6 — Cloudflare

域名未确认时在此暂停，请用户选择。

1. 创建/更新 A 记录指向源站 IPv4。
2. 不创建 AAAA，除非 Phase 1 的 IPv6 验证全部通过。
3. WS/TLS/订阅主机设置 Proxied；Reality 和 Reality XHTTP 使用 DNS only 的独立主机或源站 IP。
4. SSL/TLS 模式设置 `Full (strict)`。
5. 等待 DNS 生效，验证解析和 443 证书链。
6. 从无登录 Cookie 的外部请求订阅。
7. 若返回 Cloudflare Challenge/403，按 `docs/CLOUDFLARE.md` 创建精确 Skip 规则。

不要把切换橙云/灰云当作通用排错开关。灰云会让订阅和 WS 直达源站；如果源站 443 没有完整
TLS/Nginx 路由，就会从 Cloudflare 200/101 退化为 TLS EOF。切换后必须等待公共 DNS 生效，并分别
向 `1.1.1.1`、`8.8.8.8` 查询结果。

门禁：公共 DNS 和 TLS 正确，订阅外部请求返回 200 YAML，WAF 规则仅覆盖精确路径。

## Phase 7 — 外部订阅验证

PowerShell：

```powershell
.\scripts\verify-endpoints.ps1 \
  -Domain '<DOMAIN>' \
  -ProfileToken '<TOKEN>' \
  -EdgeDomain '<EDGE_DOMAIN>' \
  -DirectHost '<DIRECT_HOST_OR_IP>'
```

Bash：

```bash
EDGE_DOMAIN='<EDGE_DOMAIN>' DIRECT_HOST='<DIRECT_HOST_OR_IP>' \
  ./scripts/verify-endpoints.sh '<DOMAIN>' '<TOKEN>'
```

验证脚本只打印状态、长度、内容类型、结构和去敏节点角色，不打印完整订阅正文或 Token。它会严格
区分完整 profile 与 provider，并拒绝 Reality/XHTTP 使用 Proxied 边缘主机。

门禁：profile/provider 两个端点都是 200、非 HTML、无 Challenge；完整 profile 有 rule 模式、
代理组和规则，provider 只有节点；每个直连节点的 server/port/network 符合架构。

## Phase 8 — 节点隔离测试

不要切换正在承载远程控制的 Clash。

优先选择以下方式之一：

- 第二台手机/电脑；
- 临时虚拟机或容器中的 mihomo/sing-box；
- 本机新启动的独立测试内核，监听不同本地端口，不修改系统代理/TUN；
- 服务器外的测试机。

分别测试 Reality、Reality XHTTP（若安装）和 WS/TLS：

1. 配置语法检查；
2. 节点 TCP/TLS/Reality 握手；
3. 通过测试代理访问一个 HTTPS 站点；
4. 查询出口 IPv4、ASN、地区；
5. 检查 DNS 是否经过测试代理；
6. 检查配置是否引用旧服务器或 relay。

TCP 端口可达不等于协议可用。通过临时测试代理访问 `generate_204` 等 HTTPS 端点并得到预期状态，
才证明握手和出站成立。报告中必须逐个写明已测节点，不能把“两项通过”写成“所有节点通过”。

门禁：两个节点独立工作，出口属于新 VPS，旧线路关闭后理论上仍可工作。

## Phase 9 — Clash Verge 交付

按 `docs/CLASH_VERGE.md` 导入。自动化代理只负责准备、验证和指导，最终切换由用户完成。

只把 `/s/clashMetaProfiles/<TOKEN>` 作为直接导入链接。`/s/clashMeta/<TOKEN>` 是 provider；若把它
直接导入，客户端通常只有节点，没有规则组和规则，于是全局模式正常、规则模式失败。

建议先关闭 QUIC/HTTP3 测试，配置 `ipv6: false`，避免浏览器通过本地 IPv6 或 QUIC 绕过仅有的系统代理。
稳定后再逐项恢复功能。

门禁：用户分别确认全局和规则模式下网页、DNS 和出口地区正常。若只有全局模式可用，回到 profile、
rule-provider、代理组、DNS 和最后一条 `MATCH` 排查，不能把服务器重装当作第一反应。

## Phase 10 — 重启、续期和独立性验证

1. 记录服务状态后重启 VPS。
2. SSH 恢复后等待服务启动，重复 Phase 5–8 的关键测试。
3. 检查 Xray/Nginx enabled、证书续期 timer/cron、日志轮转和防火墙持久化。
4. 临时禁用旧服务器节点/relay 引用，再验证 SG 配置仍工作。
5. 上游重新生成订阅后，重新运行 Phase 7；若 XHTTP 又被写成边缘主机，先备份并运行
   `scripts/repair-clash-xhttp-host.sh`，再重新验证。
6. 完成 `CHECKLIST.md`，提交去敏交付报告。

门禁：完整重启后仍通过，且不依赖旧服务器。只有用户批准才删除旧资源。
