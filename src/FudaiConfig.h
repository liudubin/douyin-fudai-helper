//
//  FudaiConfig.h
//  抖音福袋助手 —— 公共头:符号混淆 + 配置项 + 统计 + 日志
//
//  重要:本文件必须最先 #import(所有自有类的 @interface 声明之前),
//  否则 @interface 用原名而 @implementation 用混淆名会编译失败。
//  被 hook 的抖音类名是运行时字符串,不受此影响。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#pragma mark - 符号混淆(解包 dylib 验证:原类名出现次数应为 0)

#define FudaiConfig         Fu0
#define FudaiEngine         Fu1
#define FudaiPanel          Fu2
#define FudaiProbe          Fu3
#define FudaiScan           Fu4
#define FudaiUI             Fu5
#define FudaiGlassCard      Fu6
#define FudaiSwitchRow      Fu7
#define FudaiSegmented      Fu8
#define FudaiStatBar        Fu9
#define FudaiBanner         FuA
#define FudaiFloatingBall   FuB
#define FudaiProbeResult    FuC

#pragma mark - 版本/构建时间(编译期注入)

extern NSString *FudaiVersionString(void);
extern NSString *FudaiBuildTimeString(void);
#define FUDAI_VER   FudaiVersionString()
#define FUDAI_BUILD FudaiBuildTimeString()

#ifndef FUDAI_VERSION
#define FUDAI_VERSION "0.0.0"
#endif
#ifndef FUDAI_BUILD_TIME
#define FUDAI_BUILD_TIME "dev"
#endif

#pragma mark - 巡逻模式

typedef NS_ENUM(NSInteger, FuPatrolMode) {
    FuPatrolModeDetectOnly = 0,   // 仅检测:只看不参与
    FuPatrolModeAutoJoin   = 1,   // 自动参与:留在当前房间
    FuPatrolModeFullPatrol = 2,   // 全自动巡逻:无福袋自动切台
};

extern NSString *FuPatrolModeName(FuPatrolMode mode);

#pragma mark - 配置单例

@interface FudaiConfig : NSObject

+ (instancetype)shared;

- (void)reload;
- (void)save;

// 总开关
@property (assign, nonatomic) BOOL master;
@property (assign, nonatomic) FuPatrolMode patrolMode;

// 功能开关(与面板一一对应)
@property (assign, nonatomic) BOOL superBagAuto;      // 超级福袋(金福袋)· 自动参与,含口令
@property (assign, nonatomic) BOOL normalBagAuto;     // 普通福袋 · 自动参与
@property (assign, nonatomic) BOOL codeCommentAuto;   // 评论口令自动发送
@property (assign, nonatomic) BOOL roomPatrolAuto;    // 直播间自动巡逻(无福袋自动切台)
@property (assign, nonatomic) BOOL winBanner;         // 中奖横幅提醒
@property (assign, nonatomic) BOOL detectOnly;        // 仅检测模式(灰度观察)

// 参数
@property (assign, nonatomic) NSInteger patrolMinSec;     // 无福袋判定下限(秒)
@property (assign, nonatomic) NSInteger patrolMaxSec;     // 无福袋判定上限(秒)
@property (assign, nonatomic) NSInteger bagWaitSec;       // 进房后等福袋出现的宽限(秒)
@property (assign, nonatomic) NSInteger maxJoinPerRoom;   // 单房间最多参与次数
@property (assign, nonatomic) NSInteger dailyJoinLimit;   // 今日参与上限(0=不限)
@property (assign, nonatomic) NSInteger patrolRoomTarget; // 巡逻房间目标数(0=不限)
@property (assign, nonatomic) NSInteger tapDelayMs;       // 点按后的稳定等待(毫秒)
@property (copy, nonatomic) NSString *codeTemplate;       // 口令兜底模板
@property (assign, nonatomic) BOOL showFloatingBall;      // 显示悬浮球
@property (assign, nonatomic) BOOL redPacketAuto;        // 红包口令自动抓取发送
@property (assign, nonatomic) BOOL instantGrab;          // 福袋秒抢(不等节拍,150ms 快速通道)

// 统计(按日切)
@property (assign, nonatomic) NSInteger todayJoin;    // 今日参与
@property (assign, nonatomic) NSInteger todayWin;     // 今日中奖
@property (assign, nonatomic) NSInteger todayRedpack; // 今日红包口令
@property (assign, nonatomic) NSInteger patrolRooms;  // 巡逻房间
@property (copy, nonatomic) NSString *statDay;        // 统计归属日 yyyy-MM-dd

- (void)refreshDayIfNeeded;
- (void)bumpJoin;
- (void)bumpWin;
- (void)bumpRedpack;
- (void)bumpRoom;
- (void)resetToday;

// 主题色(福袋粉)
- (UIColor *)accentColor;

@end

#pragma mark - 日志

extern void FuLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
extern void FuLogClear(void);
extern NSArray<NSString *> *FuLogLines(void);
extern NSString *FuLogSnapshot(void);
