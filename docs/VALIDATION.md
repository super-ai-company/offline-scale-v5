# v1.2.0 候选版验收 / Candidate validation

当前状态：**软件检查通过；新版本硬件验收待完成。** 本候选版不能被描述为已完成真机最终验收。

Status: **software checks passed; hardware acceptance pending for this version.**

## 已运行 / Executed

验收日期：2026-10-01，环境为 macOS、Flutter 3.47.5、Dart 3.13.4。

| 检查 / Check | 命令 / Command | 结果 / Result |
|---|---|---|
| 静态分析 / Analysis | `flutter analyze` | `No issues found`, exit 0 |
| 回归测试 / Regression | `flutter test` | 26 passed；截图生成测试默认跳过 / preview generator intentionally skipped |
| 截图生成 / UI preview | `flutter test test/ui_preview_test.dart --dart-define=GENERATE_SCREENSHOTS=true` 加本地字体路径 / with local font paths | 1 passed；四张真实 Flutter 渲染预览 / four actual Flutter renders |
| Android 构建 / Build | `flutter build apk --release` | universal APK，约 101.7 MB，exit 0 |
| 签名 / Signature | Android SDK `apksigner verify --verbose --print-certs` | APK v2 signature passed；证书与 v1.1.1 相同 / same legacy certificate |
| Manifest | Android SDK `aapt dump xmltree` | no debuggable flag；backup and cleartext disabled |
| 差异卫生 / Diff hygiene | `git diff --check` | passed |
| 发布前敏感内容检查 / Publication scan | 定向检查账号、常见 token/私钥模式以及 Git 差异 / targeted account, common token/private-key pattern and diff review | 公开源码与演示截图不包含真实飞鹅凭据 / no real Feie credentials in source or demo previews |

26 项回归涵盖金额舍入、重量有效性与稳定性、菜单升级保持、语言回退、USB 打印调用参数、商品识别，以及 8 项飞鹅接口测试：HTTPS 新 URL/签名、文字状态解析、接收与出纸区别、失联后持久化保护、明确拒绝与异常回复、5000 字节限制、票据控制标签清理、并发互斥。

The regression suite covers amounts, scale validity, menu migration, language fallback, USB payloads, recognition and eight Feie adapter scenarios. The cloud transport is mocked in these tests; these results do not prove connectivity or paper output on a real printer.

## 审核修复 / Review fixes

- 新增飞鹅设置与云打印接口，UKEY 使用 Android Keystore AES-GCM 保存。
- 区分云接收、云端出纸确认、明确拒绝和结果不明；保护跨重启并阻止并发重复提交。
- 修复设置下拉框宽度溢出；购物车文字继承主题字体。
- 串口读线程增加代次隔离，退出时关闭串口；打印退出释放资源，物理打印与关闭串行化。
- 移除不存在的副屏 Activity 声明；统一 USB 小票金额的 Locale.US 小数格式。
- 保留旧包名与签名，禁止因新签名不兼容而卸载设备数据。

## 原版本证据 / Previous-version evidence

[v1.1.1 发布记录](https://github.com/lijingpan/cashiertraeV2/releases/tag/v1.1.1)记载 Rockchip 设备串口称重、USB 位图打印和切纸成功。它只证明旧版，不替代本候选版的真机测试。旧记录亦未完成外部摄像头对纸张内容的核对。

The upstream v1.1.1 release records successful Rockchip serial weighing and USB printing. This is historical evidence for that release, not acceptance of v1.2.0.

## 尚待验收 / Pending

1. 去皮与置零、关闭打印的销售流程仍待实测；当前设备覆盖安装、菜单/设置保留和稳定重量入单已通过。
2. 已指定本地飞鹅 58 mm 小票机，真实在线查询、App 设置保存、中英文测试单发送和云端已打印查询通过；人工纸张核对待完成。
3. 原 USB 小票机、商米内置机分别验收；当前无商米设备证据。
4. 指定飞鹅型号的泰文字库验收；未测前不宣称兼容。
5. 云端离线/缺纸与网络异常的真机演练；模拟测试不能代替这些实测。

The candidate remains a prerelease until current-device installation, scale behavior and actual printer paper checks are complete. No payment or live-sale transaction is required for the acceptance test.

## 签名策略 / Signing policy

旧证书 SHA-256：`3ff24ef68093422b4b612b6cd0a6fe2593d7d5008a1eb1c1fd504e42c44b4fcd`。

采用同一证书仅用于保持 GitHub 侧载升级兼容，release 构建不启用调试。CI 验证会使用临时环境的独立 debug keystore，**CI 构建不作为用户升级附件**。正式分发附件由持有原签名的本机生成；应用商店签名迁移未实施。

The distributed artifact uses the existing local signer. CI-generated APKs have a different temporary signer and are not distributed as upgrades.

## 2026-10-02 真机补充 / Device update

- rk3568_r / Android 11，1920×1080：同一发布 APK 覆盖安装成功，1.2.0(8)，保留中文、菜单、默认单价与串口设置。
- 稳定 0.460 kg × 5242.00 THB/kg = 2411.32 THB，购物车金额正确，测试未结算，现为空购物车。
- 飞鹅 58 mm 机：应用内真实在线查询、加密设置保存、单次中英文测试小票云端接收、查询最后一单“打印完成”均通过。云端报告不替代人工纸张核对。

The distributed APK was installed in place on the current scale with existing settings preserved. Stable weight and cart arithmetic were verified without checkout. The app saved Feie configuration, submitted one bilingual test and received a cloud printed confirmation. Physical paper inspection and tare/zero acceptance remain pending. Real account, printer identifiers and private device screenshots are withheld from this public record.
