# Troubleshooting Matrix

按从底到顶的层级排查，一次只验证一个假设。

| 症状 | 最可能层级 | 决定性检查 | 常见修复 |
|---|---|---|---|
| 域名不解析/解析到旧 IP | DNS | `dig A/AAAA`、`Resolve-DnsName` | 修正 A，删除未验证 AAAA，等待 TTL |
| 直连源站 443 失败 | 源站/防火墙 | `curl --resolve`、`ss -lntup` | 开端口、修 Nginx/证书/云防火墙 |
| 源站 200，Cloudflare 403 | WAF/Bot | `Cf-Mitigated`、Security Events | 精确 path + host 的 Skip 规则 |
| Windows/手机报 EOF | TLS/中间层 | `openssl s_client`、curl verbose | 修复证书/SNI/443 路由，避免异常高端口 TLS |
| 订阅 200 但导入失败 | 内容/客户端 | 检查 Content-Type、正文前几行、YAML parser | 确保不是 HTML，区分 profile 和 provider |
| 全局很快、规则模式失败 | 完整 profile/规则 | 检查是否导入 `clashMetaProfiles`、代理组、rule-provider、`MATCH` | 改用完整 profile，修规则组/DNS；不要重装 Xray |
| 电脑只能全局，手机后来可用规则 | 客户端配置差异 | 对比两端激活 URL、内核版本、规则组和 provider 状态 | 分别刷新完整 profile 并独立验收规则模式 |
| 节点列出但全部 Error | 节点参数/端口 | 独立内核日志、TCP 探测 | 对齐 UUID/key/shortId/path/SNI，开防火墙 |
| TCP 端口可达但协议握手全部超时 | Xray/inbound/错误路由 | 独立内核日志、`systemctl`、Xray log、监听进程 | 先检查/重启单个 Xray 服务，再验证；不要盲目重启整机 |
| Reality 可用，WS 不可用 | Nginx/CF/WS path | Upgrade 头、Nginx access/error log | 修正 WS path、Upgrade/Connection、源端口 |
| WS 可用，Reality 不可用 | 直连端口/Reality 参数 | 端口可达、Xray log | DNS only、开端口、对齐 public key/flow |
| WS 可用，Reality XHTTP 高端口超时 | Cloudflare/订阅渲染 | 检查 XHTTP 节点 `server` 是否为橙云域名 | 改为源站 IP/DNS only 主机，重新生成或修复 provider |
| 橙云改灰云后订阅 TLS EOF | 源站 443/TLS/Nginx | 公共 DNS、`curl --resolve` 源站、证书 SNI | 恢复边缘主机橙云，修源站 443；直连协议另用 DIRECT_HOST |
| 切换后整机断网 | 客户端控制路径 | 关闭新 profile/TUN，恢复旧配置 | 用户切回已知节点；以后隔离测试 |
| IP 检测仍是旧服务器 | 链式依赖/规则 | Clash connections、provider/relay 搜索 | 删除 relay，确保 SG 节点直接出站 |
| Reddit 显示 blocked | IP 信誉/ASN/风控 | v4/v6 分测、出口 ASN、另一 IP 对照 | 换干净 IP/ASN；清 Cookie；确认没有绕过 |
| 只有部分浏览器失败 | QUIC/IPv6/扩展 | 禁 QUIC、无痕、`curl` 经代理 | TUN 或强制代理 DNS；`ipv6: false` |
| 重启后失效 | 持久化 | `systemctl is-enabled`、timer、firewall | enable 服务、修证书续期和规则持久化 |

## 四个基础测试

服务器上分别测 IPv4/IPv6：

```bash
curl -4 -fsS https://api.ipify.org && echo
curl -6 -fsS https://api64.ipify.org && echo
curl -4 -sS -o /dev/null -w 'v4=%{http_code}\n' https://www.reddit.com/
curl -6 -sS -o /dev/null -w 'v6=%{http_code}\n' https://www.reddit.com/
```

判断：

- v4 被拒、v6 正常：IPv4 地址/ASN 信誉问题更可能；
- v4 正常、v6 被拒：IPv6 出口、路由或信誉问题；
- 两者都被拒：IP/ASN 风控或站点策略；
- VPS 两者正常但浏览器 blocked：Clash 没接管、IPv6/QUIC 绕过、Cookie/扩展或客户端规则。

“服务器位于美国/新加坡”不保证特定网站接受该 IP。数据中心 ASN 和 IP 历史信誉通常比国家标签更关键。

## TLS/订阅三点对照

同一个 URL 分别测试：

1. VPS 本机请求订阅后端；
2. 外部 `curl --resolve` 直连源站；
3. 外部普通 DNS 经 Cloudflare。

结果定位：

- 1 失败：订阅生成器/本地服务；
- 1 成功、2 失败：Nginx/证书/源站防火墙；
- 1、2 成功、3 失败：Cloudflare DNS/TLS/WAF；
- 三者成功、Clash 失败：客户端 TLS、YAML、文件权限或网络路径。

## Profile/provider 四项结构检查

不要只检查 HTTP 200。下载后只打印结构标记，不打印 Token 或完整正文：

```bash
grep -E '^(mode|ipv6|proxies|proxy-providers|proxy-groups|rules):' profile.yaml
grep -E '^(proxies|proxy-groups|rules):' provider.yaml
```

判定：

- 完整 profile：必须有 `mode: rule`、`proxy-groups:`、`rules:`，并包含 `proxies:` 或
  `proxy-providers:`；
- provider：应有 `proxies:`，不应承担完整规则配置；
- 全局模式可用、规则模式失败时，先做此检查；
- 上游重新生成订阅后必须重做，不能依赖旧截图或节点数量。

## 端口可达与协议可用的区别

`Test-NetConnection`/`nc` 成功只证明 TCP 建连。Reality/XHTTP 还需要正确 UUID、public key、shortId、
SNI、path、flow 和运行中的 inbound。使用独立测试内核通过指定节点访问 HTTPS，并结合内核日志判断：

- TCP 连接拒绝：监听/防火墙；
- TCP 可达但所有协议握手超时：Xray 服务、inbound 或路由错误；
- 只有指向边缘域名的高端口失败：Cloudflare 代理状态/渲染地址错误；
- 返回预期 HTTPS 状态且出口属于新 VPS：该指定节点通过，不代表其他节点也通过。

## 日志纪律

只截取必要时间窗口，打印前替换 UUID、Token、域名和 IP。不要把完整订阅响应贴进公开 issue。
