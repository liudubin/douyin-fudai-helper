//
//  FudaiEngine.m
//

#import "FudaiEngine.h"
#import "FudaiProbe.h"
#import "FudaiScan.h"
#import "FudaiUI.h"
#include <stdlib.h>

static NSArray<NSString *> *FuBagTextKeys(void) {
    return @[@"超级福袋", @"金福袋", @"福袋"];
}
static NSArray<NSString *> *FuSuperBagTextKeys(void) {
    return @[@"超级福袋", @"金福袋"];
}
static NSArray<NSString *> *FuJoinTextKeys(void) {
    return @[@"立即参与", @"我要参与", @"去参与", @"立即参加", @"抢福袋", @"参与抽奖"];
}
static NSArray<NSString *> *FuWinTextKeys(void) {
    return @[@"恭喜中奖", @"你已中奖", @"已中奖", @"中奖啦", @"恭喜获得", @"恭喜你抽中"];
}

@interface FudaiEngine ()
@property (assign, nonatomic) BOOL running;
@property (assign, nonatomic) BOOL inRoom;
@property (assign, nonatomic) BOOL bagSeenInRoom;
@property (assign, nonatomic) NSInteger joinedInRoom;
@property (assign, nonatomic) NSInteger patrolWaitSec;      // 本房间「无福袋」判定时长(15~45 随机)
@property (strong, nonatomic) NSDate *roomEnteredAt;
@property (strong, nonatomic) NSDate *lastActionAt;
@property (strong, nonatomic) NSDate *lastWinAt;
@property (copy, nonatomic) NSString *lastLogSignature;
@property (copy, nonatomic) NSString *roomClassChain;
@property (strong, nonatomic) NSTimer *timer;
@property (assign, nonatomic) NSInteger tickCount;
@end

@implementation FudaiEngine

+ (instancetype)shared {
    static FudaiEngine *engine;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ engine = [[FudaiEngine alloc] init]; });
    return engine;
}

#pragma mark - 生命周期

- (void)start {
    if (self.running) return;
    self.running = YES;
    [[FudaiConfig shared] refreshDayIfNeeded];
    [[FudaiProbe shared] runAsync];

    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
        [weakSelf tick];
    }];
    // 主 runloop 常见模式,面板拖动/滚动时也不断拍
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];

    FuLog(@"引擎启动 v%@ (build %@)", FUDAI_VER, FUDAI_BUILD);
    FuLog(@"当前模式:%@ · 总开关:%@", FuPatrolModeName([FudaiConfig shared].patrolMode),
          [FudaiConfig shared].master ? @"开" : @"关");
    [self fireStateChange];
}

- (void)notifyConfigChanged {
    self.roomEnteredAt = [NSDate date];
    self.lastLogSignature = nil;
    [self fireStateChange];
}

- (void)probeNow {
    FuLog(@"手动触发类名探测");
    [[FudaiProbe shared] runAsync];
}

- (void)resetToday {
    [[FudaiConfig shared] resetToday];
    FuLog(@"今日统计已清零");
    [self fireStateChange];
}

- (void)fireStateChange {
    if (self.onStateChange) self.onStateChange();
}

#pragma mark - 心跳

- (void)tick {
    self.tickCount += 1;
    FudaiConfig *cfg = [FudaiConfig shared];
    [cfg refreshDayIfNeeded];

    if (self.tickCount % 5 == 0 && self.onStateChange) self.onStateChange();

    if (!cfg.master) {
        if (self.inRoom) {
            self.inRoom = NO;
            self.roomClassChain = nil;
            FuLog(@"总开关关闭,停止巡逻");
            [self fireStateChange];
        }
        return;
    }

    if (self.tickCount % 60 == 0 && [cfg dailyJoinLimit] > 0 && cfg.todayJoin >= cfg.dailyJoinLimit) {
        [self logOnce:[NSString stringWithFormat:@"今日参与已达上限 %ld,暂停参与", (long)cfg.dailyJoinLimit]];
        return;
    }

    BOOL live = [FudaiScan looksLikeLiveRoom];
    if (live && !self.inRoom) {
        [self enterRoom];
    } else if (!live && self.inRoom) {
        [self exitRoom];
    }
    if (!self.inRoom) return;

    [self detectWin];

    BOOL detectOnly = cfg.detectOnly || cfg.patrolMode == FuPatrolModeDetectOnly;
    BOOL bagVisible = [FudaiScan hasVisibleViewMatching:FuBagTextKeys()];

    if (bagVisible) {
        if (!self.bagSeenInRoom) {
            self.bagSeenInRoom = YES;
            [self logOnce:@"检测到福袋出现"];
        }
    } else {
        [self maybePatrol];
        return;
    }

    if (detectOnly) {
        [self logOnce:@"仅检测模式:福袋可见,不参与"];
        return;
    }

    [self stepJoin];
}

- (void)enterRoom {
    FudaiConfig *cfg = [FudaiConfig shared];
    self.inRoom = YES;
    self.bagSeenInRoom = NO;
    self.joinedInRoom = 0;
    self.roomEnteredAt = [NSDate date];
    self.lastLogSignature = nil;
    self.roomClassChain = [FudaiScan topViewControllerClassChain];

    NSInteger minSec = MAX(5, cfg.patrolMinSec);
    NSInteger maxSec = MAX(minSec, cfg.patrolMaxSec);
    NSInteger span = maxSec - minSec;
    self.patrolWaitSec = minSec + (span > 0 ? (NSInteger)arc4random_uniform((uint32_t)(span + 1)) : 0);

    if (cfg.patrolMode == FuPatrolModeFullPatrol) [cfg bumpRoom];
    FuLog(@"进入直播间:%@", self.roomClassChain);
    FuLog(@"本房间无福袋判定 %lds,单房间最多参与 %ld 次", (long)self.patrolWaitSec, (long)cfg.maxJoinPerRoom);
    [self fireStateChange];
}

- (void)exitRoom {
    FuLog(@"离开直播间,累计参与 %ld 次", (long)self.joinedInRoom);
    self.inRoom = NO;
    self.bagSeenInRoom = NO;
    self.joinedInRoom = 0;
    self.roomClassChain = nil;
    self.lastLogSignature = nil;
    [self fireStateChange];
}

#pragma mark - 参与

- (void)stepJoin {
    FudaiConfig *cfg = [FudaiConfig shared];
    if (self.joinedInRoom >= cfg.maxJoinPerRoom) {
        [self logOnce:@"本房间参与次数已达上限"];
        return;
    }
    NSDate *now = [NSDate date];
    if (self.lastActionAt && [now timeIntervalSinceDate:self.lastActionAt] * 1000.0 < (double)cfg.tapDelayMs) {
        return;
    }

    BOOL superBag = [FudaiScan hasVisibleViewMatching:FuSuperBagTextKeys()];
    if (superBag && !cfg.superBagAuto) {
        [self logOnce:@"超级福袋可见,但开关未开"];
        return;
    }
    if (!superBag && !cfg.normalBagAuto) {
        [self logOnce:@"普通福袋可见,但开关未开"];
        return;
    }

    if ([FudaiScan tapFirstMatching:FuJoinTextKeys()]) {
        self.lastActionAt = now;
        self.joinedInRoom += 1;
        [cfg bumpJoin];
        FuLog(@"%@参与成功(本房间第 %ld 次,今日第 %ld 次)",
              superBag ? @"超级福袋" : @"普通福袋",
              (long)self.joinedInRoom, (long)cfg.todayJoin);
        [self fireStateChange];

        if (cfg.codeCommentAuto) {
            NSString *code = [FudaiScan extractCode];
            if (code.length) {
                NSString *finalCode = code;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    if ([FudaiScan injectComment:finalCode]) {
                        FuLog(@"口令已发送:%@", finalCode);
                    } else {
                        FuLog(@"口令发送失败(未找到输入框或发送按钮)");
                    }
                });
            } else if (superBag) {
                FuLog(@"超级福袋未取到口令文本,跳过评论注入");
            }
        }
        return;
    }

    // 还没弹出参与按钮:点福袋入口把面板调出来,下一拍再找按钮
    if ([FudaiScan tapFirstMatching:FuBagTextKeys()]) {
        self.lastActionAt = now;
        [self logOnce:@"福袋面板入口已点开"];
    } else {
        [self logOnce:@"福袋可见但没有可点按的参与入口"];
    }
}

#pragma mark - 中奖

- (void)detectWin {
    FudaiConfig *cfg = [FudaiConfig shared];
    if (![FudaiScan hasVisibleViewMatching:FuWinTextKeys()]) return;
    NSDate *now = [NSDate date];
    if (self.lastWinAt && [now timeIntervalSinceDate:self.lastWinAt] < 20.0) return;
    self.lastWinAt = now;
    [cfg bumpWin];
    FuLog(@"检测到中奖提示(今日第 %ld 次)", (long)cfg.todayWin);
    if (cfg.winBanner) {
        [FudaiBanner showWithText:[NSString stringWithFormat:@"🎉 福袋中奖 · 今日第 %ld 次", (long)cfg.todayWin]];
    }
    [self fireStateChange];
}

#pragma mark - 巡逻

- (void)maybePatrol {
    FudaiConfig *cfg = [FudaiConfig shared];
    if (cfg.patrolMode != FuPatrolModeFullPatrol || !cfg.roomPatrolAuto) return;
    if (cfg.detectOnly) return;
    if (cfg.patrolRoomTarget > 0 && cfg.patrolRooms >= cfg.patrolRoomTarget) {
        [self logOnce:[NSString stringWithFormat:@"已达巡逻房间目标 %ld,停止切台", (long)cfg.patrolRoomTarget]];
        return;
    }
    if (!self.roomEnteredAt) self.roomEnteredAt = [NSDate date];
    NSTimeInterval stayed = [[NSDate date] timeIntervalSinceDate:self.roomEnteredAt];
    if (stayed < (NSTimeInterval)self.patrolWaitSec) {
        [self logOnce:[NSString stringWithFormat:@"本房间无福袋,%.0fs 后切台", (double)self.patrolWaitSec - stayed]];
        return;
    }
    if ([FudaiScan switchToNextRoom]) {
        [cfg bumpRoom];
        self.roomEnteredAt = [NSDate date];
        self.bagSeenInRoom = NO;
        self.joinedInRoom = 0;
        FuLog(@"无福袋切台完成,累计巡逻房间 %ld", (long)cfg.patrolRooms);
        [self fireStateChange];
    } else {
        [self logOnce:@"切台失败:当前页面不是可翻页的信息流"];
        self.roomEnteredAt = [NSDate date];
    }
}

#pragma mark - 日志节流

- (void)logOnce:(NSString *)text {
    if (!text.length) return;
    if ([text isEqualToString:self.lastLogSignature]) return;
    self.lastLogSignature = text;
    FuLog(@"%@", text);
}

#pragma mark - 对外文本

- (NSString *)engineLine {
    return [NSString stringWithFormat:@"%@ · v%@ 面板(底部 sheet 全宽)",
            [[FudaiProbe shared].result statusLine], FUDAI_VER];
}

- (NSString *)stateSummary {
    FudaiConfig *cfg = [FudaiConfig shared];
    if (!cfg.master) return @"已停止";
    if (!self.inRoom) return @"待命(未在直播间)";
    return [NSString stringWithFormat:@"运行中 · %@", FuPatrolModeName(cfg.patrolMode)];
}

- (NSString *)diagnosticText {
    FudaiConfig *cfg = [FudaiConfig shared];
    FudaiProbeResult *probe = [FudaiProbe shared].result;
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:@"===== 抖音福袋助手 诊断 ====="];
    [lines addObject:[NSString stringWithFormat:@"版本: %@ (build %@)", FUDAI_VER, FUDAI_BUILD]];
    NSString *hostVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    [lines addObject:[NSString stringWithFormat:@"目标: 抖音 %@ / com.ss.iphone.ugc.Aweme / relaxin 无根",
                      hostVersion ?: @"?"]];
    [lines addObject:[NSString stringWithFormat:@"总开关: %@   模式: %@   心跳: %@",
                      cfg.master ? @"开" : @"关",
                      FuPatrolModeName(cfg.patrolMode),
                      self.running ? @"运行" : @"停止"]];
    [lines addObject:[NSString stringWithFormat:@"当前:%@", [self stateSummary]]];
    [lines addObject:[NSString stringWithFormat:@"直播间类名链: %@", self.roomClassChain ?: @"(不在直播间)"]];
    [lines addObject:@"-- 开关 --"];
    [lines addObject:[NSString stringWithFormat:@"超级福袋自动参与:%d 普通福袋自动参与:%d 口令评论:%d",
                      cfg.superBagAuto, cfg.normalBagAuto, cfg.codeCommentAuto]];
    [lines addObject:[NSString stringWithFormat:@"自动巡逻:%d 中奖横幅:%d 仅检测:%d",
                      cfg.roomPatrolAuto, cfg.winBanner, cfg.detectOnly]];
    [lines addObject:@"-- 参数 --"];
    [lines addObject:[NSString stringWithFormat:@"切台判定 %ld~%lds  福袋等待 %lds  单房间上限 %ld  今日上限 %ld  巡逻目标 %ld",
                      (long)cfg.patrolMinSec, (long)cfg.patrolMaxSec, (long)cfg.bagWaitSec,
                      (long)cfg.maxJoinPerRoom, (long)cfg.dailyJoinLimit, (long)cfg.patrolRoomTarget]];
    [lines addObject:[NSString stringWithFormat:@"口令模板: %@", cfg.codeTemplate]];
    [lines addObject:@"-- 统计 --"];
    [lines addObject:[NSString stringWithFormat:@"今日参与 %ld · 今日中奖 %ld · 巡逻房间 %ld (归属日 %@)",
                      (long)cfg.todayJoin, (long)cfg.todayWin, (long)cfg.patrolRooms, cfg.statDay]];
    [lines addObject:@"-- 类名探测 --"];
    [lines addObject:[probe reportText] ?: @"(尚未完成探测)"];
    [lines addObject:@"-- 可见文本快照 --"];
    [lines addObject:[FudaiScan joinedTextsLimit:40]];
    [lines addObject:@"-- 日志 --"];
    [lines addObject:FuLogSnapshot()];
    return [lines componentsJoinedByString:@"\n"];
}

@end
