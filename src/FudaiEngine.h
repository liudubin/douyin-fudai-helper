//
//  FudaiEngine.h
//  福袋自动化调度:总开关 → 直播间判定 → 福袋检测 → 参与 → 口令 → 切台 → 中奖提醒
//
//  分层原则(与面板/日志一致):
//    · 判定全部来自视图可见文本(FudaiScan),不依赖私有 API,版本漂移不会崩溃
//    · 每一步动作失败都只记日志,不进异常状态,不阻断后续巡逻
//    · 仅检测 / detectOnly 打开时,引擎只观测不点按(灰度观察用)
//

#import "FudaiConfig.h"

@interface FudaiEngine : NSObject

+ (instancetype)shared;

/// App 启动完成后调用:启动心跳 + 首次类名探测
- (void)start;

/// 心跳是否在跑
@property (nonatomic, readonly) BOOL running;

/// 面板刷新回调(状态/统计变化时触发,主线程)
@property (copy, nonatomic) void (^onStateChange)(void);

/// 面板改完配置后调用:重算房间计时,避免旧计时立刻触发切台
- (void)notifyConfigChanged;

/// 参数页「立即探测」按钮
- (void)probeNow;

/// 复制诊断正文
- (NSString *)diagnosticText;

/// 面板底栏的引擎行(与截图一致:「类名探测中 · v0.7.2 面板(底部 sheet 全宽)」)
- (NSString *)engineLine;

/// 当前状态一行摘要(面板顶栏「运行中/已停止」与参数页展示)
- (NSString *)stateSummary;

/// 清空今日统计
- (void)resetToday;

@end
