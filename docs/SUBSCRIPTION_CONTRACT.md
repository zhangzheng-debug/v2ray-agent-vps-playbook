# Clash 订阅契约与节点路由门禁

这份契约解决两个容易混淆、但后果完全不同的问题：客户端应导入哪条订阅，以及每个节点应该连接
Cloudflare 边缘还是直接连接 VPS。

## 两个 URL 不是同一种配置

| 端点 | 内容 | 正确用途 | 误用后的典型现象 |
|---|---|---|---|
| `/s/clashMetaProfiles/<TOKEN>` | 完整 Clash 配置：`mode: rule`、代理组、规则和 provider 引用 | 直接导入 Clash Verge / Clash Meta for Android | 正常支持规则模式 |
| `/s/clashMeta/<TOKEN>` | 只有 `proxies:` 的节点 provider | 由完整 profile 的 `proxy-providers` 引用 | 当作完整配置导入后通常只能用全局模式 |

用户索要“Clash 直链”时，默认交付完整 profile URL。provider URL 必须明确标注为“仅供 provider
引用，不能当作完整规则配置导入”。不能因为两条 URL 都返回 HTTP 200 YAML，就认为它们可以互换。

## 渲染后节点路由契约

| 节点类型 | `server` 应指向 | Cloudflare 状态 | 推荐端口 |
|---|---|---|---|
| VLESS WS/TLS、VMess WS/TLS | `EDGE_HOST` | Proxied | 443 |
| 完整 profile/provider 下载 | `EDGE_HOST` | Proxied | 443 |
| VLESS Reality Vision | `DIRECT_HOST` 或 VPS 公网 IP | DNS only / 直连 IP | 独立高位 TCP 端口 |
| VLESS Reality XHTTP | `DIRECT_HOST` 或 VPS 公网 IP | DNS only / 直连 IP | 独立端口，除非已证明所用 CDN 支持该协议和端口 |

普通 Cloudflare 橙云不是任意 TCP 反向代理。尤其不能让 Reality/XHTTP 高端口节点继续使用
`EDGE_HOST`；即使 TCP 探测偶尔可达，协议握手仍会失败。

上游订阅生成器可能把 CDN 地址复用到 XHTTP 节点。每次生成或更新订阅后，都必须检查最终 YAML，
不能只看“生成了几个节点”。

## 自动验证

PowerShell：

```powershell
$env:PROFILE_TOKEN = '<TOKEN>'
.\scripts\verify-endpoints.ps1 `
  -Domain 'edge.example.com' `
  -EdgeDomain 'edge.example.com' `
  -DirectHost 'direct.example.com'
```

Bash：

```bash
PROFILE_TOKEN='<TOKEN>' \
EDGE_DOMAIN='edge.example.com' \
DIRECT_HOST='direct.example.com' \
./scripts/verify-endpoints.sh 'edge.example.com'
```

验证器会拒绝以下配置：

- “完整 profile”缺少 `mode: rule`、`proxy-groups:` 或 `rules:`；
- provider 被伪装成完整 profile；
- 未明确允许时完整 profile 使用 `ipv6: true`；
- Reality/XHTTP 节点使用 Proxied 边缘主机；
- Proxied 边缘主机被用于 Cloudflare 不支持的高端口；
- 推荐架构缺少 Reality 或 WS 节点。

## 上游重新生成后的修复

优先在上游菜单/配置中让 Reality/XHTTP 输出直连地址。如果生成器仍把 `EDGE_HOST` 写入 XHTTP，
可以在服务器上先备份，再修复已渲染的 Clash provider：

```bash
sudo ./scripts/repair-clash-xhttp-host.sh \
  'edge.example.com' \
  'direct.example.com'
```

脚本只修改名称含 `VLESS_Reality_XHTTP` 的 Clash 节点块，并在
`/etc/v2ray-agent/playbook-backups/` 创建备份。它是渲染后修复，不是上游源码补丁；每次重新生成
订阅后必须重跑验证，必要时重跑修复。

## “独立测试可用”的准确含义

独立测试是启动一个不占用当前 Clash 端口、不修改系统代理/TUN 的临时 mihomo/sing-box 内核，
通过指定节点访问 HTTPS 测试地址。返回 `204` 说明该节点完成了协议握手并能出站；它不代表：

- 手机和电脑的规则配置一定正确；
- 其余节点也已验证；
- 所有网站都接受该 VPS 的 IP/ASN；
- IPv6、QUIC、TUN 和系统代理都没有其他路径。

报告必须写清楚测试了哪个节点、使用什么内核、是否改变系统代理、目标 HTTP 状态以及出口地区。

## 全局可用、规则不可用

如果全局模式下 YouTube 4K 流畅，而规则模式断网或只有部分网站可用，节点和服务器主链路通常已经
通过；下一步应检查完整 profile、规则组、rule-provider 下载、DNS 和最后一条 `MATCH`，而不是重装
Xray。首先确认客户端导入的是 `clashMetaProfiles`，不是纯 `clashMeta` provider。
