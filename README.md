# 抖音福袋助手(Douyin Fudai Helper) v0.7.2

面向 **抖音 40.7.0(iOS, `com.ss.iphone.ugc.Aweme`)+ relaxin 无根越狱** 的 Theos deb 插件,
按截图里的「福袋助手」面板 1:1 还原功能与界面:底部 sheet 全宽面板、三个 tab、统计三列、
总开关、三档巡逻模式、六个功能开关、复制诊断 / 隐藏面板、脚注引擎行。

## 直接下载(免本地编译)

每次推送 main 或打 tag 都会在 GitHub Actions 上用 Theos 编译无根 deb:

- **Release 下载**:[v0.7.2 deb](https://github.com/liudubin/douyin-fudai-helper/releases/download/v0.7.2/com.zhipu.fudaihelper_0.7.2_iphoneos-arm64.deb)
  (sha256 `5a33e10b15a78d0448fa7743de72459609d3d4fdcca5e7309dd2bf86ec294b82`)
- 最新构建产物(artifact):仓库 Actions 页 → 对应 run → Artifacts
- 装机:`dpkg -i xxx.deb` 后 `killall -9 Aweme`(relaxin 无根路径 `/var/jb/…` 已由包内置)

---

## 1. 功能对照(截图 → 实现)

| 截图项 | 实现位置 | 说明 |
| --- | --- | --- |
| 福袋助手 · 总开关 | 主页 / `master` | 关闭后心跳立即停手,不做任何点按 |
| 巡逻模式:仅检测 / 自动参与 / 全自动巡逻 | 主页分段控件 / `patrolMode` | 三档互斥,对应 `FuPatrolMode` |
| 今日参与 / 今日中奖 / 巡逻房间 | 主页统计条 | 按 `yyyy-MM-dd` 日切,持久化到偏好 |
| 超级福袋 · 自动参与(含口令) | `superBagAuto` + `codeCommentAuto` | 金福袋/超级福袋文本命中后参与,并尝试验证口令评论 |
| 普通福袋 · 自动参与 | `normalBagAuto` | 左上角普通福袋 |
| 评论口令自动发送 | `codeCommentAuto` | 从可见文本抽「口令:xxxx」→ 灌入评论框并发送 |
| 直播间自动巡逻(15-45s) | `roomPatrolAuto` + `patrolMinSec/MaxSec` | 无福袋超过随机判定时长即切台 |
| 中奖横幅提醒 | `winBanner` | 独立的 `UIWindow`(Alert+10)顶部横幅,不挡操作 |
| 仅检测模式(灰度观察) | `detectOnly` | 只记日志,不点按 |
| 参数 / 日志 tab | `FuPanelVC` | 参数可改并即时保存;日志环形 400 行、可刷新/清空 |
| 复制诊断 | `FudaiPanel.copyDiagnostic` | 环境+开关+参数+统计+类名探测+可见文本+日志 |
| 隐藏面板 | `closeTapped` | 收起 sheet,不影响引擎继续跑 |
| 脚注「引擎:类名探测中 · v0.7.2 面板(底部 sheet 全宽)」 | `FudaiEngine.engineLine` | 探测状态实时更新 |

入口:**悬浮球**(可拖动,位置记忆)+ **抖音设置页** 右上角礼物按钮 / 右下角悬浮按钮。

---

## 2. 目录结构

```
douyin-fudai-helper/
├── control                  # 包信息(iphoneos-arm64 = 无根架构)
├── Makefile                 # Theos,支持 THEOS_PACKAGE_SCHEME=rootless
├── FudaiHelper.plist        # 只注入 com.ss.iphone.ugc.Aweme
├── src/
│   ├── Tweak.x              # Logos 入口:设置页入口 + 启动引擎
│   ├── FudaiConfig.{h,m}    # 配置/统计/日切/环形日志(符号混淆 Fu0)
│   ├── FudaiScan.{h,m}      # 视图层级:取窗口/顶层VC/取文本/点按/口令/评论注入/切台
│   ├── FudaiProbe.{h,m}     # 类名探测引擎(面板脚注那行)
│   ├── FudaiEngine.{h,m}    # 状态机:进房→检测→参与→口令→切台→中奖
│   ├── FudaiUI.{h,m}        # 玻璃卡片/开关行/分段控件/统计条/中奖横幅
│   └── FudaiPanel.{h,m}     # 悬浮球 + 底部 sheet 面板(主页/参数/日志)
├── tools/
│   ├── fu_check.py          # 无工具链环境的静态自检(括号/方法声明/属性名)
│   └── objc_dump.py         # 从 IPA 导出 ObjC 类名/方法名(证据复现)
└── docs/class-probe-evidence.md   # 40.7.0 二进制实测类名证据
```

所有自有类经 `FudaiConfig.h` 里的宏改名为 `Fu0…FuC`,解包 dylib 时搜不到原始类名。

---

## 3. 构建(relaxin 无根越狱)

```bash
export THEOS=~/theos
git clone --recursive https://github.com/theos/sdks ~/theos/sdks   # 需要 iPhoneOS15+ SDK

cd douyin-fudai-helper
make clean package THEOS_PACKAGE_SCHEME=rootless
# 产物:packages/com.zhipu.fudaihelper_0.7.2_iphoneos-arm64.deb
```

安装与生效:

```bash
scp packages/*.deb root@<设备IP>:/var/mobile/
ssh root@<设备IP>
dpkg -i /var/mobile/com.zhipu.fudaihelper_0.7.2_iphoneos-arm64.deb
killall -9 Aweme     # 或 respring 后重开抖音
```

- `control` 里 `Architecture: iphoneos-arm64` 对应无根布局(`/var/jb`),relaxin/Dopamine 系直接可用。
- 有根环境去掉 `THEOS_PACKAGE_SCHEME=rootless` 重新打包即可。

---

## 4. 使用

1. 打开抖音 → 右下角出现粉色礼物悬浮球(可拖到任意位置)。
2. 点悬浮球 → 面板从底��弹出;**主页** 开总开关、选巡逻模式、按需开功能开关。
3. **参数** 页可调判定时长、单房间/今日上限、巡逻房间目标、口令模板,并可「立即探测」。
4. **日志** 页看实时动作;出问题点「复制诊断」把文本发给维护者。

> 建议首轮:模式选「仅检测」跑一场直播,确认日志能识别出福袋与中奖文案,再切「自动参与」。

---

## 5. 引擎原理(为什么稳)

- **判定来自可见文本**:每秒遍历当前 window 的视图树(节点上限 8000、深度 60),读
  `UILabel.text` / `UIButton.title` / 输入框 `text|placeholder` / `accessibilityLabel`,
  命中「福袋/超级福袋/立即参与/恭喜中奖…」即进入对应分支。
- **动作走公开语义**:就近找 `UIControl` 发 `TouchUpInside`,否则 `accessibilityActivate`——不伪造触摸事件。
- **口令**:正则 `口令[:：]?\s*([^\s，,。；;|]{2,16})` 抽出后写入评论输入框并触发发送
  (优先 `textFieldShouldReturn:`,其次「发送」按钮)。
- **切台**:取面积最大的可滚动信息流容器,`setContentOffset` 翻一页;找不到就记日志不硬来。
- **类名探测**:`objc_getClassList` 一过,按「福袋族/直播族/评论族」关键词归类并统计方法数,
  同时核对 40.7.0 实测种子类(见 `docs/class-probe-evidence.md`)是否在场。
- **可观测**:每个动作都写日志;所有失败只降级,不抛异常、不循环点按(点按后 `tapDelayMs` 冷却)。

---

## 6. 参数

| 参数 | 默认 | 含义 |
| --- | --- | --- |
| 无福袋判定下限/上限 | 15 / 45 s | 进房后随机取一个值作为「无福袋」等待 |
| 进房等福袋宽限 | 8 s | 进房抖动保护 |
| 点按后稳定等待 | 600 ms | 冷却,防止连点 |
| 单房间最多参与 | 3 | 每个直播间参与次数上限 |
| 今日参与上限 | 0(不限) | 达到后当天不再参与 |
| 巡逻房间目标 | 8 | 达到后停止切台 |
| 口令兜底模板 | 口令 | 抽不到口令时的兜底文本 |

配置写在 `com.zhipu.fudaihelper` 偏好域(抖音沙盒内),卸载插件后残留一份 plist,不影响 App。

---

## 7. 排障

| 现象 | 处理 |
| --- | --- |
| 悬浮球不出现 | 参数页确认「显示悬浮球」开着;或用设置页入口 |
| 日志一直「待命(未在直播间)」 | 直播间 VC 类名不含 Live/Room 且层级无 HTSLive 视图 → 复制诊断看「可见文本快照」 |
| 参与了但不涨「今日中奖」 | 中奖文案不在关键词表内 → 复制诊断反馈可见文本,补关键词 |
| 切台无效 | 当前页不是可翻页信息流(如福袋详情浮层),退出浮层后会自动恢复 |
| 以为插件没生效 | 看 `Console` 里 `[Fudai] 注入成功…` 一行 |

---

## 8. 自检

无 iOS 工具链时先跑静态自检(括号/方法声明/属性名/宏映射):

```bash
python tools/fu_check.py
```

真机验证顺序:注入日志 → 类名探测结果(参数页)→ 仅检测识别福袋 → 自动参与 → 口令 → 切台 → 中奖横幅。
