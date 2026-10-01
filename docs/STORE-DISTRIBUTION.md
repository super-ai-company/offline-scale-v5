# 官网与 Google Play 双渠道 / Website and Google Play

## 已实施 / Implemented

| 渠道 / Channel | 包名 / Application ID | 更新 / Updates |
|---|---|---|
| 官网 website | `com.vdamov3.cashier_trae` | 用户手动检查公司 GitHub；验证大小、SHA256、版本、签名后覆盖安装 |
| Google Play play | `com.superaicompany.offlinescale` | 设置打开 Google Play；不申请 APK 安装权限，原生层拒绝 APK 安装 |

Both builds share cashier, scale, local printers, precision settings and optional Feie fallback. Website builds retain the legacy signer and application ID for in-place upgrades. Play uses a separate application ID because the legacy debug certificate cannot be used as a production upload key. The two apps have separate databases and settings; switching channels does not migrate data. Do not uninstall the original cashier to switch channels.

两个渠道共用收银、称重、本地打印、精度设置和默认关闭的飞鹅备用打印。官网旧版可保留数据覆盖升级。Play 独立包名，两者数据独立，不能把安装 Play 版描述为原版无损升级。

```sh
flutter build apk --release --flavor website
flutter build appbundle --release --flavor play
```

The second command currently produces an **unsigned validation candidate, not a production upload**. Production needs a dedicated upload signing key and a passing native-library audit. Never upload a validation candidate.

## 发布门禁 / Release gates

2026-10-02 实际 Play Console 显示身份审核中、Android 设备验证及电话验证待完成，创建应用被锁定。账号创建、提交资料不代表已批准；没有创建应用、上传或审核回执。

Native audit found ARM64 `libserial_port.so` and `libautoreplyprint.so` use ELF LOAD alignment `0x1000` (4 KB). Keep hardware support intact; obtain a 16 KB compatible build from each SDK vendor or authorized source and rebuild/test on both 4 KB scale hardware and a 16 KB device. Changing ZIP alignment alone does not repair these libraries. `libjnidispatch.so` is aligned to `0x10000`.

Actual AAB audit checks 18 libraries and finds 5 incompatible libraries: the two ARM64 libraries above, plus x86_64 `libautoreplyprint.so`, `libserial_port.so`, and `libjnidispatch.so`. The ARM64 JNA library passes alignment; x86_64 JNA does not. Run the standard-library-only checker with your registered Python runtime: `tools/check_play_native.py build/app/outputs/bundle/playRelease/app-play-release.aab`. Its current nonzero exit is an expected release blocker, not a passed validation.

个人新账号正式发布前通常需要至少 12 名测试者连续加入封闭测试 14 天，并申请正式发布权限。不能伪造测试记录；以当前 Console 要求为准。

Sources: [self-update permission policy](https://support.google.com/googleplay/android-developer/answer/16558241), [16 KB compatibility](https://developer.android.com/guide/practices/page-sizes), [personal-account testing](https://support.google.com/googleplay/android-developer/answer/14151465).

## 商店文案 / Listing copy

Name: Offline Scale V5

EN short description: Offline weighing cashier with local receipt printing and optional cloud fallback.

中文简述：离线称重收银、本地小票打印，可选飞鹅云备用打印。

EN description: Manage products, calculate weight-based prices and print receipts on compatible Android cashier scales. Configure weight and currency precision, rounding or truncation, and local printer settings. Core cashier and local printing work without internet. Feie cloud printing is optional, disabled by default and requires your own Feie account and compatible printer. Industrial scale serial access and listed printers are required for hardware functions; ordinary phones do not become weighing scales. No payment processing is provided. Updates for this distribution are handled through Google Play.

中文详情：在兼容 Android 收银秤上管理商品、按重量计算金额和打印小票。可设置重量与金额小数位、四舍五入或截位，以及本地打印机参数。核心收银和本地打印不依赖互联网。飞鹅云为默认关闭的可选备用打印，需要用户自己的飞鹅账号和兼容打印机。硬件功能要求兼容秤串口权限和兼容表中的打印机；普通手机不能直接称重。本应用不处理支付。此渠道通过 Google Play 更新。

Screenshots: existing `docs/screenshots/cashier-en.png`, `cashier-zh.png`, `precision-settings-en.png`, `precision-settings-zh.png`, `feie-settings-en.png`, `feie-settings-zh.png`. These show actual functionality; capture Play update UI after final hardware-compatible build. Store icon and feature graphic must meet Console dimensions before submission.

## 隐私说明草稿 / Privacy disclosure draft

Products, prices, settings, local image training and receipt calculations are stored on the device. Camera recognition is optional and processed locally. Local printing sends receipt content to the connected printer. Enabling Feie sends receipt content and printer/account identifiers to the configured Feie regional service; the user supplies credentials, stored using Android Keystore protection. Internet access is needed for cloud printing and store updates, not core offline cashier use. No advertising or analytics SDK is integrated by this project. Uninstalling the app deletes its local data; there is no developer-hosted user account to delete. Publish a policy URL with verified developer support contact before submitting; finalize Data Safety declarations from actual data flows, including optional Feie, rather than declaring every build collects nothing.

商品、价格、设置、图像训练及本地订单计算保存在设备。可选摄像头识别在本机处理。本地打印仅向连接的打印机发送小票。开启飞鹅后，小票内容及打印机/账号标识发送至配置的飞鹅区域服务；用户提供凭据，使用 Android Keystore 保护。项目未集成广告或分析 SDK。卸载会删除本地数据。正式提交前须公开含已核实联系地址的隐私政策，并按真实可选云打印数据流填写数据安全表。

## Apple

Android APK/AAB cannot be submitted to the App Store. An iOS product needs its own build, supported scale/printer transport and real-device validation; the current Android serial/AAR integrations do not constitute iOS support. Do not advertise an iOS download or App Store approval for this build.
