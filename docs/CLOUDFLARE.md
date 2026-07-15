# Cloudflare Configuration

## DNS

推荐拆分：

| 用途 | 记录 | Proxy status | 说明 |
|---|---|---|---|
| Reality 主线路 | `direct.example.com` A | DNS only | 客户端直达源站端口 |
| WS/TLS + 订阅 | `edge.example.com` A | Proxied | Cloudflare 443 到 Nginx |

不要给未验证的 IPv6 创建 AAAA。错误 AAAA 会让部分客户端优先连接一个不可用或绕过代理的 IPv6 路径。

## SSL/TLS

使用 `Full (strict)`：

- 浏览器到 Cloudflare：有效边缘证书；
- Cloudflare 到源站：源站证书必须有效且匹配域名；
- 不使用 `Flexible`，否则源站段没有 TLS，也容易产生重定向循环和错误安全假设。

## 订阅端点被 403/Challenge

典型证据：

- 源站本机请求返回 200；
- `curl --resolve` 直连源站返回 200；
- 公网经 Cloudflare 返回 403、HTML Challenge，或响应头含 `Cf-Mitigated: challenge`；
- Clash/手机报 fetch failed、EOF 或无法解析 YAML。

这不是订阅 YAML 本身的问题，而是非浏览器客户端无法完成 Cloudflare Challenge。

创建一条 **Skip** 自定义规则，只匹配两个精确端点。表达式模板见
`templates/cloudflare-skip-expression.txt`。

可以在该精确范围内跳过：

- 其余自定义规则；
- Rate Limiting Rules；
- Managed Rules；
- Super Bot Fight Mode Rules；
- Browser Integrity Check；
- Security Level。

产品界面的可选项会变化，以当前 Cloudflare UI 为准。不要关闭整个 Zone 的安全功能，也不要用
`starts_with(http.request.uri.path, "/s/")` 放行所有订阅前缀。

## 验证顺序

1. `Resolve-DnsName` / `dig` 确认 A/AAAA。
2. `curl --resolve` 直连源站验证证书和正文。
3. 普通 `curl` 经 Cloudflare，检查 HTTP 状态、Content-Type、`Cf-Mitigated`。
4. 无痕浏览器不是充分测试；Clash 是无 Cookie 客户端，应以 curl/客户端结果为准。
5. Cloudflare Security Events 中确认只有精确订阅请求命中 Skip。

## 常见误区

- 橙云不是任意 TCP 反代；普通套餐只适合支持的 HTTP/HTTPS/WebSocket 端口。
- DNS 生效不等于源站证书正确。
- 浏览器能打开不等于 Clash 能下载，浏览器可能通过了 Challenge 并持有 Cookie。
- 把端口从 URL 去掉只会改为 443，不会自动修复源站路由或 TLS。
