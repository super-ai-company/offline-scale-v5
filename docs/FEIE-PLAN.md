# 离线电子秤实施计划 / Offline Scale implementation plan

## 目标与范围 / Scope

保留 Android 电子秤的离线称重、菜单、购物车和 USB/商米打印。在设置中增加可选飞鹅云小票打印；飞鹅模式需要互联网。目标仓库为 `super-ai-company/offline-scale-v5`，来源为 `lijingpan/cashiertraeV2` 的 `codex/offline-ai` 分支，保留来源历史。

Keep weighing, menu management, cart and USB/SUNMI printing offline. Add an optional Feie Cloud receipt backend in Settings. Cloud printing requires internet; it does not provide offline Feie printing.

## 已实施 / Implemented

1. 默认 USB/SUNMI 本地优先，飞鹅独立开关默认关闭；本地连接失败且未发送时才可备用；支持中国、亚太、欧洲站。地区必须与开发者账号一致。
2. USER、9 位 SN 和 UKEY 配置；UKEY 使用 Android Keystore AES-GCM 加密保存，禁止 Android 自动备份；无内置账号或密钥。
3. 使用 HTTPS、2026 年独立接口 URL、表单 POST 和 SHA1(USER + UKEY + UNIX timestamp)。不重定向、不记录认证参数或原始云端错误。
4. 状态查询、测试小票、最后一单出纸状态查询。打印机须先在对应飞鹅开发者后台绑定；应用不自动添加或删除平台设备。
5. 提交前检查设备在线。云端返回订单 ID 表示已接收，购物车只清空一次；“已接收”和“已确认打印”分别显示。
6. 请求前持久化防重发标记；超时、断线、异常回复和进程中断保持标记。并发提交互斥；无自动重试。结果不明时用户先查飞鹅后台和实体纸张，再确认解除保护。
7. 商品名和店名清理控制标签，金额沿用购物车的分币舍入，单份小票上限 5000 UTF-8 字节。

Settings always prioritize local USB/SUNMI. Optional cloud backup is disabled by default and only runs after local connection failure before sending a ticket. Uncertain local writes retain a durable guard and never automatically transfer to cloud. Settings select the account region. UKEY is encrypted at rest by Android Keystore. The adapter uses the documented split HTTPS endpoints, signed form POSTs, bounded timeouts and response sizes. Status checks precede submission. A durable resend guard and in-process mutex prevent blind retry after lost replies; acceptance and paper confirmation are distinct states. Cloud device binding stays in the official portal.

## 使用流程 / Setup

1. 在对应地区的飞鹅开发者后台确认小票机已绑定 USER。打印机标签 KEY 与账号 UKEY 是两种不同凭据。
2. 设置 → 打印设置 → 启用飞鹅备用打印，选择账号地区，填写 USER、UKEY、SN。
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


## 摄像头商品自动识别（开发分支） / Produce recognition branch

### API、设备与范围 / API, hardware and scope

本阶段**无需申请 API、云账号或支付识别费用**。复用随 APK 打包的 MediaPipe MobileNet V3 Small 特征模型和设备本地 SQLite 样本。图片只在本机提取特征，临时图片处理后释放，不上传。该通用模型不是已经训练好的蔬果分类器；“相似度”不是准确率或概率。先验证小范围商品，再决定是否需要训练专用离线分类模型；未来训练可以在现有受控 GPU 上执行，不能据此擅自开通收费 API。

No cloud API is required. The bundled feature model and local sample database work offline. This generic embedder is not a validated produce classifier; similarity is not accuracy. A future produce-specific model depends on measured failures and a separately validated dataset.

固定摄像头朝向秤盘，避免面向顾客的摄像头；画面必须完整覆盖单种商品，保持背景和补光稳定。首批建议土豆、白萝卜、胡萝卜等少量 SKU，但实际商品及镜头位置由门店确认。不同价格等级、产地或品种不能仅靠外观可靠区分；混放不同商品、遮挡袋和手进入画面要人工点选。摄像头不可用时正常手动收银。

Fix the camera toward the tray. Start with a small confirmed catalogue; use one category per weighing cycle. Grade, origin, opaque bags and mixed produce require manual confirmation. Camera failure must not block checkout.

### 已实现 / Implemented

- 独立分支 `feat/offline-produce-recognition`，候选版本 `1.3.0-dev.1+12`；不移动 `v1.2.3` 标签，不合并主分支，不修改下载网站或发布正式版。
- 自动识别独立开关默认关闭；打开后重量有效、稳定至少 1 秒才拍摄。每个稳定周期最多核对 4 帧，可人工重新识别。
- 候选列表沿用本地商品与单价，点选即可采用；不自动入购物车、不结账、不打印。未知或相似商品显示人工确认提示。
- 试验性自动选择开关默认关闭。启用后仍要求至少 2 类有效称重商品、每类至少 5 个有效样本、相似度至少 0.94、领先次选至少 0.08、连续 3 帧一致。这些是保守的初始规则，**没有真实商品校准前不保证准确率**。
- 重量变化、失联、后台、导航和人工改单价使在途识别作废；人工选择后锁住本次周期，商品移走后重置。已由摄像头选择的商品在新周期清除，避免沿用上次价格。
- 用户已确认当前镜头朝天、后续可以加配件，本轮硬件仅验收接入与界面，不把朝天画面作为商品准确率证据。
- 设置支持检测、固定选择商品摄像头；采样与自动识别共用所选镜头。固定配件断开时拒绝自动切到另一镜头，保留人工收银。按所选镜头隔离样本特征，换镜头需要重新采样；不删除旧镜头样本。自动选择还要求固定选择镜头。
- 设置、采样和自动预览切换前释放摄像头；错误保留手动收银。中文、英文、泰文提示完整。
- Android debug 包针对本次 ARM64 RK3568 设备、压缩原生库，使用 `.visiondev` 独立安装标识；独立数据库和设置，正式版不被覆盖。不要使用 release 构建覆盖正式版做本阶段测试。
- `ProduceRecognitionPolicy.evaluate()` 提供可复用判定接口；`ProduceDecision.toJson()` 提供 code、候选 id、相似度和单价。`ProduceScanCycle` 可单独测试重量状态、连续帧和过期结果。

### 采样、校准及验收 / Sampling, calibration and acceptance

1. 商品管理创建真实称重商品与实际单价，拍摄样本；每类先收集 20–40 张，覆盖角度、数量、外观和光线。5 张仅是软件最低门槛，不能代替完整采样。训练样本不得同时计入验收样本。
2. 独立测试版验证镜头朝向、预览、采样保存、移走归零后重识别、人工改单价锁定、进入设置/商品管理及前后台切换。正式版保留不卸载；测试数据不复制飞鹅密钥。
3. 每 SKU 用未参与采样的实物至少 30 次测试，记录总次数、正确第一候选、误选、拒判和耗时；另测未登记商品、相似商品、空盘、手、袋子、暗光、失联及不同价格等级。不把自动化向量测试当真实蔬果准确率。
4. 自动选择上线门槛：上述固定测试集误选为 0；正确自动选择率至少 95%，其余拒判；中位响应时间小于 3 秒。此门槛只是验收目标，**尚未实测达成**。达不到时保持候选辅助模式，改进样本或训练专用离线模型，再用新独立测试集复验。
5. 按用户此前说明，断网测试由用户在本机执行，避免中断无线调试；需确认关闭 Wi-Fi 后识别、称重及本地打印仍可用，飞鹅开关保持关闭。本轮未声称已完成新增识别流程的断网真机验收。
6. 开发测试和 APK 构建完成后提交分支及 PR；真实商品验收仍待用户配合，经 fujane 审核后才能安排正式发布。独立 debug APK 仅作设备测试，不能当生产下载包。

Capture diverse samples, then evaluate independent real produce and unknown objects. Release criteria are targets, not measured performance. Keep assist mode until the held-out test set passes. The debug APK has separate storage and must not overwrite the deployed app. Production release remains subject to hardware acceptance and review.

### 后续专用模型阶段 / Dedicated model phase

若实测显示同色蔬菜、袋装商品或不同光线下通用特征区分不足，使用经授权采集的数据训练轻量专用分类模型（包括 unknown/background），按实物批次划分训练、验证与独立测试，导出设备可运行模型并测量 CPU 耗时、内存和热稳定性。只有验证有效才替换模型，并为样本建立新的模型版本，不能混用旧特征。本阶段不伪造土豆/萝卜样本，不自动创建商品和价格。


### 调试命令接口 / Debug command interface

只在独立 `.visiondev` debug 包启用，通过已授权 ADB `run-as` 使用应用私有目录，不开网络端口。`tool/vision_control.py --serial <明确的秤序列号> --json` 从标准输入读取 JSON，始终输出结构化 JSON；失败退出码非 0。共享设备操作必须由 `LocalEnv/bin/device-lock run <serial> offline-scale-vision -- <命令>` 包住。应用需要在前台运行。

- `{"action":"status"}`：查询重量状态、当前商品、识别配置、商品和当前镜头样本数；不返回飞鹅账号或密钥。
- `{"action":"cameras"}`：列出实际摄像头、镜头方向和旋转角。
- `{"action":"configure","configuration":{"camera_enabled":true,"auto_enabled":true,"auto_select":false,"camera_name":"0"}}`：默认 dry_run；显式增加 `"apply":true` 才保存设置。
- `{"action":"select","item_id":123,"apply":true}`：人工选择已存在商品，锁住本次识别；不入购物车或结账。
- `{"action":"capture_sample","item_id":123,"apply":true}`：真实拍摄并保存该已存在商品的特征。相机不可用则失败；超时/进程中断后先查询 sample_counts，不盲目重试。request_id 在执行前持久化，重复请求不重复采样。
- `{"action":"recognize"}`：实际相机拍摄，只输出判定，不选商品。
- `{"action":"replay","embedding":[1.0,0.0]}`：用指定特征重放当前镜头样本的判定（维度必须匹配真实模型）。输出 `accepted/unknown/ambiguous/needs_samples/no_samples` 等 code，score 不等于准确率。

命令接口不提供打印、付款或生产数据修改；正式 APK 拒绝 diagnosticsPath。`capture_sample` 接口不允许创建商品或价格，防止测试数据污染真实菜单。
