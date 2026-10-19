# 类名证据链(抖音 40.7.0 / AwemeCore)

本插件里所有**写死的抖音类名**都来自对随包二进制的静态导出,不是猜测。
运行时依旧以「探测结果为先」:类名缺失时只记日志,不点按、不崩溃。

## 复现方式

```bash
python tools/objc_dump.py "抖音_40.7.0.ipa" objc_dump
grep -Ei 'chest' objc_dump/classnames.txt
grep -Ei 'sendcomment' objc_dump/methnames.txt
```

## 二进制事实(实测)

| 项 | 值 |
| --- | --- |
| 主二进制 | `Payload/Aweme.app/Frameworks/AwemeCore.framework/AwemeCore` |
| 大小(解压) | 1,026,662,944 B |
| Mach-O | magic `feedfacf`,filetype 6 (dylib),ncmds 181 |
| 加密 | `LC_ENCRYPTION_INFO_64.cryptid = 0`(**已解密**,可直接读元数据) |
| `__TEXT,__objc_classname` | 文件偏移 `0x2eb237e0`,大小 5,445,399 B |
| `__TEXT,__objc_methname` | 文件偏移 `0x2c51c970`,大小 39,874,152 B |
| 导出类名 | 165,427 条 |
| 导出方法名 | 1,453,252 条 |

## 直播间福袋相关(已确认存在)

```
HTSLiveChestInfo
HTSLiveChestCardInfo            HTSLiveChestCardBonusInfo
HTSLiveChestOpenedInfo          HTSLiveChestOpenedInfo_WinningUser
HTSLiveWaitChestOpenInfo        HTSLiveWaitChestOpenInfo_AchieveTaskUser
HTSLiveChestTask                HTSLiveChestGameContent / HTSLiveChestGameSetting
HTSLiveEffectChestCard          HTSLiveEffectChestCard_User
HTSLiveLinkmicChestGameRoot     HTSLiveLinkmicChestGameStatus
HTSLiveRedpackActivityInfo      HTSLivePreviewPromotionSyncData_LuckyBag
AWEIMCodeGenLuckyBagPrizeModel  AWELivePreStreamInnerRoomFansLuckyMoneyView
```

这些类里 `Chest`/`WaitChestOpen`/`WinningUser` 一组正是「福袋 → 等待开奖 → 中奖名单」
的业务语义,插件把它作为「当前版本是否具备福袋能力」的确定性判据
(FudaiProbe 的 seeds 列表),用于参数页展示与诊断。

## 评论链路(已确认存在)

```
sendComment:
sendComment:withColors:
sendComment:withColors:completion:
sendComment:commentContext:completion:
sendComment:flowTime:elapsedTime:callBack:
sendComment:enterSource:requestSource:trackParams:completion:
commentInputViewControllerSendCommentFinished:responseModel:model:error:
enableSendComment / canSendComment
```

插件没有直接 hook 这些选择器:它们的签名随版本变动,误 hook 会让输入框卡死。
口令发送走的是 `FudaiScan` 的输入框注入(写 text + 触发 target-action),
失败只记日志——与截图里「type=3 口令参与走评论 hook 发送」的意图一致,
但实现上选择了不绑死私有签名的路径。

## 设置页入口(已确认存在)

40.7.0 起抖音设置页有两套体系,插件都挂:

- `AWESettingPageBaseController`(新版设置页基类)
- `AWEGeneralSettingViewController`(旧版通用设置)
- `AWESettingsTableViewController`(40.7.0 起设置首页,DUX 自定义导航栏)
