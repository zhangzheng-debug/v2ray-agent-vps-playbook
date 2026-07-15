# Deployment Checklist

## 输入与控制通道

- [ ] SSH 主机指纹已确认
- [ ] 登录方式可用，云厂商 Console 可作为恢复通道
- [ ] 当前 Clash/系统代理/TUN 未被自动化代理切换
- [ ] 域名和 Cloudflare 权限已确认，秘密未写入 Git

## 服务器

- [ ] 系统、架构、时间、磁盘、内存和公网 IPv4 正常
- [ ] 现有服务和端口冲突已检查
- [ ] IPv6 已端到端验证，或明确禁用且没有 AAAA
- [ ] Nginx、Xray、证书、防火墙配置已有可读备份
- [ ] 上游 README、release 和安装脚本已在本次部署中重新检查
- [ ] Nginx 配置测试通过，Xray 服务 active
- [ ] 证书 SAN 正确且有效期正常

## Cloudflare

- [ ] A 记录内容正确
- [ ] Reality 主线路没有错误套用橙云
- [ ] Reality XHTTP 若存在，最终订阅使用直连主机/IP，而不是橙云边缘主机
- [ ] WS/TLS 和订阅域名通过 443 提供服务
- [ ] SSL/TLS 为 Full (strict)
- [ ] WAF Skip 仅命中精确主机和两个精确随机路径
- [ ] 没有关闭区域级安全功能

## 外部验证

- [ ] 完整 profile：无 Cookie 请求返回 200 YAML
- [ ] provider：无 Cookie 请求返回 200 YAML
- [ ] 完整 profile 含 rule 模式、代理组和规则；provider 只含 proxies，两个 URL 已明确标注
- [ ] 已审计每个节点的 server/port/network，Proxied 主机只承载支持的 443 HTTP/WS 路径
- [ ] 无 `Cf-Mitigated: challenge`，无 EOF/TLS 协商错误
- [ ] Reality 节点真实握手并访问 HTTPS
- [ ] WS/TLS 节点真实握手并访问 HTTPS
- [ ] 出口 IP、ASN 和地区属于新 VPS
- [ ] 配置中没有旧服务器 relay、链式 provider 或依赖

## 客户端与恢复

- [ ] Clash 配置语法通过
- [ ] 全局模式和规则模式分别验收；若只有全局可用，未把部署标记为完成
- [ ] IPv6 策略与部署一致
- [ ] 用户亲自执行最终切换并确认网络正常
- [ ] VPS 重启后所有验证重新通过
- [ ] 自动启动、日志轮转、证书续期任务正常
- [ ] 备份位置和回滚命令已交付
- [ ] 仓库/交付文档敏感信息扫描通过
- [ ] 旧服务器仍保留，或用户已明确批准删除
