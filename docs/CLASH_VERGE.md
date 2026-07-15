# Clash Verge Safe Import and Cutover

## 为什么不能由远程自动化直接切换

如果 Codex 正通过当前代理控制电脑，切换到尚未验证的新节点会立刻切断自己的控制通道。
因此，准备和验证可以自动化，最后一次“选中节点”必须由用户完成。

## 导入前

1. 保持当前已知可用节点、系统代理和 TUN 状态不变。
2. 用 `verify-endpoints` 确认订阅 URL 在无 Cookie 条件下返回 200 YAML。
3. 备份 Clash Verge 当前配置。
4. 确认新 profile 中：
   - `ipv6: false`，除非 IPv6 已端到端验证；
   - 有独立的 SG 节点组；
   - 没有旧服务器 relay 或 proxy-provider 依赖；
   - Reality 和 WS/TLS 至少各一个节点。

## 安全导入

1. 打开“订阅”。
2. 把完整 profile URL 粘贴进“订阅文件链接”，点击导入。
3. 不要把 provider URL 当成完整配置导入；provider 只含 `proxies:`，不含完整规则和代理组。
4. 导入后先查看配置和节点列表，不立即激活或切换。
5. 如 Clash Verge 报“文件丢失/变更已撤销”，退出应用后检查其 profile 目录权限、杀毒软件隔离、
   配置文件名冲突和磁盘状态，再重新导入。

## 切换步骤（用户执行）

1. 保留旧订阅卡片，不删除。
2. 激活新 SG profile。
3. 先选 Reality 主节点；若失败，立即切回旧 profile。
4. 打开 IP 检测，确认地区和 ASN 是新 VPS。
5. 测试 DNS、HTTPS、GitHub、Google/YouTube 等基础站点。
6. 再测试 WS/TLS 备用节点。
7. 稳定一段时间并完成 VPS 重启复测后，才考虑停用旧服务器。

## 系统代理与 TUN

- 系统代理只覆盖遵守 Windows 代理设置的应用；浏览器扩展、QUIC 或 IPv6 可能形成不同路径。
- TUN 覆盖面更广，但启动/切换会影响 Codex 远程控制和 SSH。
- 初次验收先用系统代理和 `ipv6: false`，必要时禁用浏览器 QUIC/HTTP3；确认稳定后再单独测试 TUN。
- 不要同时改变“节点、profile、TUN、IPv6、DNS”五个变量，否则失败后无法定位。
