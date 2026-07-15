# Architecture and Trust Boundaries

## 流量路径

```text
                         ┌─ VLESS Reality Vision ───────────────┐
Client ── proxy policy ──┤   direct host / IPv4 + dedicated port├─ Xray ── Internet
                         │   no Cloudflare proxy                │
                         └─ VLESS WS/TLS ─ Cloudflare :443 ─────┘
                                                │
Subscription client ─ HTTPS exact token path ───┴─ Nginx ─ profile/provider
```

## 为什么至少保留两条不同技术路径

- Reality 主线路没有 CDN/WebSocket 额外开销，也不依赖 Cloudflare HTTP 代理兼容性。
- WS/TLS 备用线路使用普通 HTTPS/443，适合对非标准端口不友好的网络。
- 两条线路共享服务器，但不共享完整的传输故障面；证书或 Cloudflare 问题不会直接否定 Reality。

这不是要求打开越多协议越好。协议数量越多，验证矩阵越大。默认两条经过验证的独立线路足够。

## 信任边界

| 边界 | 保存什么 | 不应保存什么 |
|---|---|---|
| 本机安全凭据 | SSH key、Cloudflare Token | 不进入 Git、不出现在截图 |
| VPS | Xray 私钥、UUID、订阅文件 | 权限最小化，日志不打印完整 URL |
| Cloudflare | DNS、证书边缘、WAF 规则 | 不保存 Reality private key |
| GitHub 仓库 | 文档、占位符、只读检查脚本 | 无真实 IP、域名、Token、UUID |
| Clash 客户端 | 完整订阅和节点秘密 | 不上传公开 issue 或公开 gist |

## DNS 与代理模式

- `direct.example.com`：A 记录，DNS only，用于 Reality 或其他直连协议。
- `edge.example.com`：A 记录，Proxied，用于 WS/TLS 443 和订阅。
- 如果只使用一个主机名，Reality 节点不要连接橙云返回的 Anycast IP；应使用源站 IP，同时把
  Reality `serverName` 设为协议实际要求的值。
- 不发布 AAAA，除非 VPS、路由、防火墙、Xray、DNS、客户端和出口测试全部支持 IPv6。

## 验证的三层模型

1. **分发层**：客户端能否下载正确 YAML？
2. **传输层**：节点能否完成握手并转发 HTTPS？
3. **出口层**：外站看到的 IP/ASN/地区是否为目标 VPS？

任何一层成功都不能替代另两层。
