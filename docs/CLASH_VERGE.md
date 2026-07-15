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

## 先确认链接类型

- 直接导入 Clash Verge/Clash Meta for Android：使用
  `/s/clashMetaProfiles/<TOKEN>`。
- `/s/clashMeta/<TOKEN>` 只有 `proxies:`，只能被完整 profile 的 `proxy-providers` 引用。
- 如果导入后只有节点列表、全局模式可用，但规则模式没有代理组或无法分流，优先检查是否误导入了
  provider URL。

两条链接都可能返回 HTTP 200，因此“能下载”不能证明“链接用途正确”。导入前应运行
`verify-endpoints`，确认 profile 有 rule 模式、代理组和规则。

## 安全导入

1. 打开“订阅”。
2. 把 `/s/clashMetaProfiles/<TOKEN>` 完整 profile URL 粘贴进“订阅文件链接”，点击导入。
3. 不要把 provider URL 当成完整配置导入；provider 只含 `proxies:`，不含完整规则和代理组。
4. 导入后先查看配置和节点列表，不立即激活或切换。
5. 如 Clash Verge 报“文件丢失/变更已撤销”，退出应用后检查其 profile 目录权限、杀毒软件隔离、
   配置文件名冲突和磁盘状态，再重新导入。

## 全局快、规则失败

全局模式下 YouTube 4K 流畅，至少说明当前选中节点、服务器出站和主要传输链路可用；这时不要先
重装 Xray。依次检查：

1. 激活的是完整 profile，而不是 provider；
2. `mode: rule`、`proxy-groups:`、`rules:` 都存在；
3. 规则引用的代理组名称确实存在，且组内选中了 SG 节点；
4. rule-provider 能下载，不是 403、Challenge、超时或旧服务器链接；
5. 最后一条 `MATCH` 没有错误指向 `DIRECT` 或不存在的组；
6. DNS 规则和代理规则一致，没有海外域名被本地 DNS/直连路径截走。

电脑和 Android 客户端可以使用不同内核版本、缓存和规则提供器，所以手机规则模式恢复不等于电脑
配置也正确；应分别验收。

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

## 隔离测试报告规范

临时 mihomo 内核监听独立本地端口、且没有修改系统代理/TUN时，可以称为“独立测试”。报告必须写明：

- 实际测试的节点名称/协议，而不是笼统写“所有节点”；
- 临时内核端口与当前 Clash 不冲突；
- 通过临时代理访问的 HTTPS 目标及返回状态（例如 `204`）；
- 出口 IP/ASN/地区；
- 未验证的项目，例如手机规则、QUIC、IPv6 或其他节点。
