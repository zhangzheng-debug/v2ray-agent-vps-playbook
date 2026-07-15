# Sanitized Deployment Postmortem

## 摘要

目标是在一台新加坡 VPS 上部署多协议代理、Cloudflare 域名订阅和 Clash Verge 配置，并让它不依赖即将到期的旧服务器。

最终结果：客户端通过 VLESS Reality Vision 独立连接新加坡 VPS，出口检测显示新加坡数据中心 ASN；
同时保留 WS/TLS 443 备用节点和可被 Clash/Android 下载的订阅。

## 主要故障链

1. 上游脚本已生成多个节点，但最初的高端口 HTTPS 订阅在 Windows 和 Android 出现 fetch failed/EOF。
2. 服务器本机访问订阅返回 200，说明订阅内容存在。
3. 强制特定 TLS 版本曾能改变结果，提示端口/TLS 中间层兼容性问题。
4. 为域名增加标准 443 Nginx 路由后，源站测试正常。
5. 经 Cloudflare 的公网请求仍返回 403，响应带 Challenge 特征；浏览器与无 Cookie 客户端表现不同。
6. 添加只匹配精确订阅路径的 Cloudflare Skip 规则后，完整 profile 和 provider 均返回 200。
7. Clash 导入后曾过早切换未验证节点，导致控制电脑断网；恢复旧线路后改用隔离验证和用户最终切换。
8. 清除旧服务器中继依赖后，Reality 节点出口确认属于新加坡 VPS。
9. 后续发现 provider URL 被当作完整 Clash 直链交付：全局模式很快，但桌面规则模式缺少完整配置。
10. 把边缘主机改为 DNS only 后，Reality 高端口解析正确，但订阅/WS 失去 Cloudflare 443 并出现
    源站 TLS EOF；说明单一主机的橙云/灰云切换无法同时满足两类路径。
11. 恢复 Proxied 边缘主机后，订阅返回 200、WS Upgrade 返回 101；同时把 Reality XHTTP 的最终
    provider 地址改成直连主机/IP。
12. Xray 单服务重启后，隔离内核对指定 Reality 节点的 HTTPS 测试返回预期状态；全过程未切换本机
    当前代理。

## 根因

这不是单一“脚本没安装好”：

- 分发层：非标准订阅端口存在 TLS 兼容性风险；
- 边缘层：Cloudflare 对无浏览器 Cookie 的订阅请求发出 Challenge；
- 客户端层：过早切换新配置切断了远程控制路径；
- 设计层：初期没有明确区分直连 Reality、Cloudflare WS 和订阅三个路径。
- 订阅契约层：最初的验证器只检查“像 YAML”，没有区分完整 profile 与 provider；
- 渲染层：上游生成结果把 CDN 地址复用给 Reality XHTTP，未在客户端交付前逐节点审计；
- 证据层：曾把有限的隔离测试结论描述得过宽。

## 修复

- 使用标准 HTTPS 443 暴露订阅和 WS/TLS；
- Cloudflare 设为 Full (strict)；
- 仅对两个精确随机订阅 URL 跳过相关安全检查；
- 不发布未验证 AAAA，Clash 默认 `ipv6: false`；
- Reality 主节点直达源站，WS/TLS 作为 Cloudflare 备用；
- 完整 profile 作为客户端导入链接，provider 只供 profile 引用；
- 增加节点路由审计，拒绝 Reality/XHTTP 使用 Proxied 边缘主机；
- 对上游重新生成后复发的 XHTTP 地址提供带备份的渲染后修复脚本；
- 最终切换交给用户，自动化只做隔离验证；
- 使用出口 IP/ASN/地区和重启复测作为完成门禁。

## 防复发措施

- `AGENTS.md` 把控制通道安全设为第一门禁；
- Runbook 固定“源站 -> Cloudflare -> 订阅 -> 握手 -> 出口 -> 重启”的验证顺序；
- 提供端点检查和敏感信息扫描脚本；
- 端点检查现在验证 profile/provider 结构、IPv6 策略和逐节点边缘/直连角色；
- Cloudflare WAF 使用精确表达式模板；
- 公开仓库只保存占位符和去敏证据。
