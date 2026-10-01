# 飞鹅云打印接入方案 / Feie Cloud integration

## 目标与范围 / Scope

保留 Android 电子秤的离线称重、菜单、购物车和 USB/商米打印。在设置中增加可选飞鹅云小票打印；飞鹅模式需要互联网。目标仓库为 `super-ai-company/offline-scale-v5`，来源为 `lijingpan/cashiertraeV2` 的 `codex/offline-ai` 分支，保留来源历史。

Keep weighing, menu management, cart and USB/SUNMI printing offline. Add an optional Feie Cloud receipt backend in Settings. Cloud printing requires internet; it does not provide offline Feie printing.

## 已实施 / Implemented

1. 设置选择 USB/SUNMI 或飞鹅云；支持中国、亚太、欧洲站。地区必须与开发者账号一致。
2. USER、9 位 SN 和 UKEY 配置；UKEY 使用 Android Keystore AES-GCM 加密保存，禁止 Android 自动备份；无内置账号或密钥。
3. 使用 HTTPS、2026 年独立接口 URL、表单 POST 和 SHA1(USER + UKEY + UNIX timestamp)。不重定向、不记录认证参数或原始云端错误。
4. 状态查询、测试小票、最后一单出纸状态查询。打印机须先在对应飞鹅开发者后台绑定；应用不自动添加或删除平台设备。
5. 提交前检查设备在线。云端返回订单 ID 表示已接收，购物车只清空一次；“已接收”和“已确认打印”分别显示。
6. 请求前持久化防重发标记；超时、断线、异常回复和进程中断保持标记。并发提交互斥；无自动重试。结果不明时用户先查飞鹅后台和实体纸张，再确认解除保护。
7. 商品名和店名清理控制标签，金额沿用购物车的分币舍入，单份小票上限 5000 UTF-8 字节。

Settings select the backend and account region. UKEY is encrypted at rest by Android Keystore. The adapter uses the documented split HTTPS endpoints, signed form POSTs, bounded timeouts and response sizes. Status checks precede submission. A durable resend guard and in-process mutex prevent blind retry after lost replies; acceptance and paper confirmation are distinct states. Cloud device binding stays in the official portal.

## 使用流程 / Setup

1. 在对应地区的飞鹅开发者后台确认小票机已绑定 USER。打印机标签 KEY 与账号 UKEY 是两种不同凭据。
2. 设置 → 打印设置 → 飞鹅云，选择账号地区，填写 USER、UKEY、SN。
3. 检查状态 → 打印测试小票 → 查询最后一张云小票；核对纸张。
4. 保存设置后收银打印。关闭打印开关可以继续离线完成销售；结果不明订单须先人工核对，避免重复纸张。

Bind the receipt printer in the portal, enter the same region and credentials in Settings, check status, print a test ticket, query its confirmation, inspect paper, then save. Printing can be disabled to finish sales offline. Do not resend uncertain orders before checking the portal and paper.

## 验收 / Acceptance

| 场景 / Scenario | 判据 / Expected result |
|---|---|
| USB 离线 / USB offline | 原称重与打印流程通过，无云请求 / Existing flow, no cloud request |
| 飞鹅在线 / Feie online | 返回订单 ID，云端确认出纸，人工核对纸张 / Order ID, cloud confirmation and inspected paper |
| 缺纸、离线 / Abnormal, offline | 不发送订单，购物车保留 / No submission; cart retained |
| 网络超时 / Lost reply | 无自动重发，重启后保护仍存在 / No auto retry; guard survives restart |
| 明确云端拒绝 / Explicit rejection | 保留购物车，可纠正配置后重试 / Retain cart; allow retry after correction |
| 并发点击 / Concurrent requests | 只允许一个云提交 / One submission only |
| 中英文 / Chinese and English | 名称、kg、单价和金额一致 / Consistent names, weight, prices and amounts |
| 泰文 / Thai | 需在具体飞鹅硬件上验收字库，不能以 USB 位图结果代替 / Verify fonts on the actual Feie device |

## 发布与回退 / Release and rollback

保留现有应用 ID 与 v1.1.1 签名证书，覆盖安装不主动清除菜单和设置。发布前必须核对 APK v2 签名、版本号、测试结果、真实设备与小票证据；未完成硬件验收时只能标为候选版。旧 APK 保留在原发布地址。版本回退可能被 Android 版本码限制，不能通过卸载绕过而丢失本地数据。

Keep the existing application ID and signing certificate for upgrades. Preserve the old release. Hardware acceptance remains a release gate; a candidate must be clearly labeled until it passes. Never uninstall a deployed app to bypass downgrade or signature restrictions.

## 官方依据 / Official references

- [亚太开发者 API / Asia Pacific API](https://developer.jp.feieyun.com/apidoc.html)
- [2026 独立接口迁移公告 / Split endpoint migration](https://help1.feieyun.com/docs/96C8PyrC)

具体测试状态见 [验收记录](VALIDATION.md)，不以实现完成替代真机验收。
