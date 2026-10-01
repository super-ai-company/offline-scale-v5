---
name: feie-offline-scale
description: 接手 Offline Scale V5 的飞鹅云备用打印配置、58mm小票、故障诊断和真实打印验收。复用已有账号与设备，不重建绑定或保存明文密钥。
---

# 离线电子秤飞鹅接入交接

先读取现有共享飞鹅技能 `/Users/shift/.agents/skills/feie-printer/SKILL.md`，运行 `/Users/shift/LocalEnv/bin/localenv route 飞鹅`。本文件是该应用的交接补充，不替代共享API适配。离开本机环境时，使用下列参数模板，由目标设备所有者配置自己的账号。

## 参数及凭据引用

| 设置 | 本机权威来源或取值 |
|---|---|
| 业务 | offline-scale-v5 |
| 云区域 | 亚太/JP，不能凭打印失败自动切换区域 |
| 官方说明 | https://developer.jp.feieyun.com/apidoc.html |
| API | `https://api.jp.feieyun.com/Api/Open/<方法后缀>` |
| USER | `registry.feieyun.account`，用登记实际字段；共享登记位于 `/Users/shift/LocalEnv/registry.json` |
| UKEY | 读取 `registry.feieyun.credential_id` 或项目凭据引用，调用既有agent-control；不得回显。应用内Android Keystore加密存储 |
| SN | `registry.feieyun.devices.offline-scale-local.sn` |
| 设备KEY | 设备标签密钥，只在绑定/硬件查询需要；与账号UKEY不同。已有设备不重复添加 |
| 纸张 | 本任务已确认58mm普通小票；不使用标签机命令 |
| 飞鹅备用 | 设置独立开关，默认关闭；开启后本地连接失败、尚未发送小票时才使用 |

账号、SN、设备状态和验证时间只维护上述原登记，本skill不复制个人账号或秘密。需要配置时从主本读取当前值，不重新向用户索要已登记参数。UKEY不可进入公共GitHub、截图、命令参数、日志或普通文档。

## API及打印规则

HTTPS POST form：`user`、`stime`（Unix秒字符串）、`apiname`、`sig=SHA1(user+UKEY+stime)`小写hex；UKEY不单独发送。打印：`Open_printMsg`，`sn`、`content`、`times=1`，5000 UTF-8字节以内；查询设备：`Open_queryPrinterStatus`；查询订单：`Open_queryOrderState`+`orderid`。区域与账号必须一致。

应用实现见 `lib/services/feie_service.dart`、`lib/services/print_service.dart`、`android/app/src/main/kotlin/com/vdamov3/cashier_trae/SecretChannel.kt`。设置先保存，再查状态。ret=0订单ID仅证明云接受；printed=true是云完成报告；实际纸面、字符与切纸需分别确认。

本地USB/SUNMI优先且不需要云账号或网络。只有本地连接明确失败且飞鹅开关开启时转云。本地发送结果不明禁止自动转云，云请求结果不明禁止重发；先查旧订单与纸面，再通过设置里的明确操作解除保护。不能因“没看到纸”换job-id偷偷再印。诊断默认只读；真打印、清队列、解绑分别需要实际用户授权。

## 金额和交接验收

重量0–3位默认3；金额0/1/2位默认2；四舍五入或截尾。重量、单价和每行金额按同一规则计价；合计为行金额之和。已有购物车固定入单规则，新设置下一单生效。主屏、副屏、本地及云小票必须一致。

先检查已有打印机状态与业务绑定；按授权单次打印真实商品，核对重量、单价、金额、中文和切纸。关闭飞鹅后断网验证本地打印，恢复网络再检查云备用。实际结果更新 `registry.feieyun` 和 `registry.offline_scale`，证据留项目；不将云接单或自动化测试写成物理出纸。当前验收以登记和发布说明为准，不能由本skill静态文字推断设备仍在线。

正式APK发布到 https://github.com/super-ai-company/offline-scale-v5/releases 。应用内手动检查正式版，校验哈希、包名、签名及递增versionCode后由Android确认覆盖安装；保留原包名与签名，不卸载旧版。更新不得自动在营业订单中执行，不能让更新检查阻断离线收银。
