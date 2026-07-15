# Security Policy

## 永远不要提交

- 真实服务器 IP、主机名和 SSH 用户组合；
- SSH 私钥、公钥注释中的邮箱、密码、Cloudflare API Token；
- Xray UUID、Reality private key、shortId、订阅随机 Token；
- Cloudflare Account/Zone ID、真实域名和账户邮箱；
- 完整 Clash 配置、订阅响应、终端历史或带秘密的截图。

使用 `templates/deployment.env.example` 中的文档保留地址和占位符。

提交前运行：

```powershell
pwsh -File .\scripts\secret-scan.ps1
```

如果秘密已经进入 Git 历史，仅删除工作区文件是不够的：先轮换秘密，再清理历史并强制更新远端。
公开 issue 中报告漏洞时也不要附真实订阅 URL。

## Cloudflare 最小权限

若使用 API Token，只授予目标 Zone 所需的 DNS Edit、Zone Read、SSL/TLS Edit 和 WAF Edit 权限；
部署结束后撤销或轮换临时 Token。优先使用已登录浏览器完成一次性操作。
