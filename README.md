# v2ray-agent VPS Playbook

一套去敏、可复用、带验证门禁的 VPS 部署手册，用于在全新 Linux 服务器上部署
[`mack-a/v2ray-agent`](https://github.com/mack-a/v2ray-agent)，并完成 Xray、域名、
Cloudflare、订阅、Clash Verge 导入、重启恢复和故障排查。

这个仓库记录了一次真实部署中踩过的坑，但不包含服务器 IP、域名、UUID、订阅令牌、
Cloudflare 标识、邮箱或 SSH 私钥。

## 给未来 Codex 的最短指令

把本仓库链接和服务器登录方式交给 Codex，然后说：

> 严格按照仓库根目录的 AGENTS.md，从服务器预检开始部署。不要切换我当前的代理或 TUN；
> Cloudflare 域名绑定前暂停让我确认。每一阶段通过验证门禁后再继续，最后完成重启复测。

如果域名和 Cloudflare 已经准备好，也可以一次提供：

- SSH 主机、用户和私钥位置；
- 要绑定的域名；
- Cloudflare 已登录的浏览器会话或最小权限 API Token；
- 是否需要 `Reality 直连 + WS/TLS CDN 备用`（推荐默认）。

## 推荐架构

```text
Clash / sing-box
  ├─ 主线路：VLESS Reality Vision ── 服务器公网 IP:独立端口
  │                                  （DNS only，不经过 Cloudflare）
  └─ 备用线：VLESS WS/TLS ── Cloudflare:443 ── Nginx ── Xray

订阅客户端 ── HTTPS://域名/s/<随机路径> ── Cloudflare:443 ── Nginx
```

关键原则：

- Reality/TCP 等非 HTTP 协议不套 Cloudflare 橙云；WS/TLS 才作为 CDN 备用线路。
- 默认只发布 IPv4；IPv6 从服务器、DNS、Xray 到客户端全部验证后才添加 AAAA。
- Cloudflare 使用 `Full (strict)`，订阅 WAF 放行必须限制到精确主机和精确随机路径。
- “订阅能下载”“节点能握手”“出口确实在目标地区”是三个独立验证项。
- 自动化代理正在控制电脑时，绝不切换本机 Clash 节点、系统代理或 TUN。

## 执行顺序

1. 从 [START_HERE.md](START_HERE.md) 复制未来部署提示词。
2. 阅读 [AGENTS.md](AGENTS.md) 的权限边界和停止点。
3. 按 [docs/RUNBOOK.md](docs/RUNBOOK.md) 逐阶段部署。
4. 使用 [scripts/preflight-server.sh](scripts/preflight-server.sh) 做只读服务器预检。
5. 安装前重新核对上游 README 和安装脚本，不把仓库中的示例当成永久不变的命令。
6. 用 [docs/CLOUDFLARE.md](docs/CLOUDFLARE.md) 配置 DNS、TLS 和精确 WAF 规则。
7. 用 `verify-endpoints` 从服务器外部验证订阅端点。
8. 用 [docs/CLASH_VERGE.md](docs/CLASH_VERGE.md) 导入，但由用户最后切换节点。
9. 完成重启复测和 [CHECKLIST.md](CHECKLIST.md) 的交付检查。

## 完成定义

只有以下项目全部满足，部署才能称为完成：

- Xray、Nginx 和证书状态正常，Nginx 配置测试通过；
- A 记录指向正确源站，AAAA 不存在或已经端到端验证；
- Cloudflare 代理状态符合每种协议的设计，TLS 为 `Full (strict)`；
- 无浏览器 Cookie 的外部客户端能以 HTTP 200 下载两个订阅端点；
- 至少一个 Reality 主节点和一个 WS/TLS 备用节点完成真实握手与网页访问；
- 出口 IP/ASN/地区与目标 VPS 一致，不依赖旧服务器中继；
- VPS 重启后服务、证书任务、防火墙规则和订阅仍正常；
- 本仓库及交付记录通过敏感信息扫描；
- 用户明确确认切换成功，旧线路才能删除。

## 仓库内容

- `AGENTS.md`：未来自动化代理必须遵守的操作契约。
- `START_HERE.md`：下次可直接复制给 Codex 的启动提示词。
- `docs/RUNBOOK.md`：从零部署的阶段化流程。
- `docs/TROUBLESHOOTING.md`：按现象定位 DNS、TLS、WAF、协议、IPv6 和客户端问题。
- `docs/LESSONS_LEARNED.md`：本次部署的经验与反模式。
- `docs/POSTMORTEM-SANITIZED.md`：去敏复盘。
- `templates/`：环境变量、Nginx、Cloudflare 和 Clash 示例。
- `scripts/`：只读预检、端点验证和仓库敏感信息检查。

## 上游与许可证

本仓库不复制或修改 `v2ray-agent` 源码。上游项目使用其自己的许可证，安装方式和功能可能更新；
执行前必须以[上游仓库](https://github.com/mack-a/v2ray-agent)当前内容为准。
本仓库原创文档和辅助脚本使用 MIT License。

## 现实边界

任何公网部署都无法承诺“永不出错”：云厂商网络、IP 信誉、Cloudflare 产品规则、上游脚本和
客户端版本都会变化。本仓库的目标是让错误尽早暴露、可定位、可回滚，并防止一次错误切换
切断操作通道。
