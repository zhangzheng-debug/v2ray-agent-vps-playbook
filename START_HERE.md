# Start Here

以后部署新 VPS 时，把本仓库 URL 和服务器交给 Codex，直接复制下面这段：

```text
请读取这个仓库根目录的 AGENTS.md、README.md、CHECKLIST.md 和 docs/RUNBOOK.md，
严格按状态机从头部署 mack-a/v2ray-agent。

服务器登录信息由我在当前会话安全提供。默认部署：
1. VLESS Reality Vision 直连主节点；
2. VLESS WS/TLS 443 经 Cloudflare 的备用节点；
3. 完整 Clash profile 和 provider 订阅；
4. IPv4 优先，没有端到端验证就不发布 AAAA，并在 Clash 使用 ipv6: false；
5. 完成源站、Cloudflare、订阅、节点握手、出口地区和 VPS 重启复测。

不要把任何秘密写入 Git，不要切换我电脑上的 Clash、系统代理或 TUN。
如果我还没指定域名，请在 Cloudflare DNS 绑定前暂停让我确认；其他安全、可回滚的
部署步骤可以自主完成。任何门禁失败都先诊断和回滚，不能跳过，也不能把部分完成说成完成。
```

同时提供：

- SSH 主机、用户和私钥位置；
- 云厂商 Console 是否可用；
- 如果已经选好，提供域名；否则等 Codex 到 Cloudflare 阶段再选择；
- Cloudflare 已登录浏览器或最小权限 API Token。

不要把密码、私钥正文、完整订阅 URL 粘贴进公开仓库、issue 或截图。
