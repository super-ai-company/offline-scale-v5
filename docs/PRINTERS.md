# 打印机兼容性 / Printer compatibility

| 类型 / Type | 接口与范围 / Interface and scope | 验证状态 / Validation |
|---|---|---|
| 原 Rockchip 收银秤 USB 小票机 / Existing Rockchip scale USB receipt printer | autoreplyprint AAR；识别 VID `0x4B43` 或 `0x0FE6`；固定 384 点 / 58 mm 位图 | 当前设备真实商品票与切纸成功、用户纸张确认；断网测试用户安排手动进行 / current product receipt and cut confirmed; Wi-Fi-off check deferred by owner |
| SUNMI 内置打印机 / SUNMI built-in | SUNMI 官方服务；制造商需为 SUNMI，状态正常后打印；384 点位图 | 代码适配，未有当前设备验收 / Adapter implemented; device unverified |
| 飞鹅云小票机 / Feie Cloud receipt printers | 对应地区飞鹅开发者 API；已绑定 9 位 SN；联网；`Open_printMsg` | 58 mm 真机真实商品票、云端打印完成、用户中文/金额/切纸确认；其他型号逐台验收 / current 58 mm receipt confirmed; other models require acceptance |
| 飞鹅标签机 / Feie label printers | 需要独立标签接口与模板 / Requires label-specific API and templates | 不支持 / Unsupported |
| 任意蓝牙、局域网或其他 VID USB 打印机 / Arbitrary Bluetooth, LAN, other USB vendors | 未提供通用 ESC/POS 适配 / No generic ESC/POS adapter | 不支持 / Unsupported |

## 本地小票 / Local receipts

本地 USB/SUNMI 路径使用 Android 字体生成位图，支持当前系统可用的中文、英文与泰文。默认纸宽 58 mm / 384 点；80 mm 不在当前纸宽验收范围。USB 库返回成功表示发送成功，仍需核对实体纸张。切纸能力取决于硬件。

The local adapter rasterizes text through Android system fonts at 384 dots. Paper width, supported fonts and cutting behavior must be verified on hardware. A successful SDK send is distinct from inspecting paper.

## 飞鹅小票 / Cloud receipts

飞鹅云路径使用官方控制标签和文本，不沿用本地 Unicode 位图。中文/英文需核对具体设备；泰文是否可出纸取决于云打印机固件字库，目前不能宣称所有飞鹅型号兼容。无需在应用中填写打印机标签 KEY，只填写已绑定设备 SN 和开发者账号 UKEY。

The Feie backend sends documented text/control tags. It does not reuse Android bitmap rendering. Thai depends on device firmware fonts. Use the account UKEY and bound SN; device KEY is needed only when binding in the official portal.
