//
//  FudaiConfig.m
//  配置持久化 + 按日统计 + 环形日志
//

#import "FudaiConfig.h"
#include <stdarg.h>

static NSString *const kSuiteName = @"com.zhipu.fudaihelper";

static NSString *const kMaster            = @"master";
static NSString *const kPatrolMode        = @"patrolMode";
static NSString *const kSuperBagAuto      = @"superBagAuto";
static NSString *const kNormalBagAuto     = @"normalBagAuto";
static NSString *const kCodeCommentAuto   = @"codeCommentAuto";
static NSString *const kRedPacketAuto     = @"redPacketAuto";
static NSString *const kRoomPatrolAuto    = @"roomPatrolAuto";
static NSString *const kWinBanner         = @"winBanner";
static NSString *const kDetectOnly        = @"detectOnly";
static NSString *const kPatrolMinSec      = @"patrolMinSec";
static NSString *const kPatrolMaxSec      = @"patrolMaxSec";
static NSString *const kBagWaitSec        = @"bagWaitSec";
static NSString *const kMaxJoinPerRoom    = @"maxJoinPerRoom";
static NSString *const kDailyJoinLimit    = @"dailyJoinLimit";
static NSString *const kPatrolRoomTarget  = @"patrolRoomTarget";
static NSString *const kTapDelayMs        = @"tapDelayMs";
static NSString *const kCodeTemplate      = @"codeTemplate";
static NSString *const kShowFloatingBall  = @"showFloatingBall";
static NSString *const kTodayJoin         = @"todayJoin";
static NSString *const kTodayWin          = @"todayWin";
static NSString *const kTodayRedpack      = @"todayRedpack";
static NSString *const kPatrolRooms       = @"patrolRooms";
static NSString *const kStatDay           = @"statDay";

#pragma mark - 版本

NSString *FudaiVersionString(void) { return @FUDAI_VERSION; }
NSString *FudaiBuildTimeString(void) { return @FUDAI_BUILD_TIME; }

NSString *FuPatrolModeName(FuPatrolMode mode) {
    switch (mode) {
        case FuPatrolModeDetectOnly: return @"仅检测";
        case FuPatrolModeAutoJoin:   return @"自动参与";
        case FuPatrolModeFullPatrol: return @"全自动巡逻";
    }
    return @"仅检测";
}

#pragma mark - 默认值

static NSUserDefaults *FuDefaults(void) {
    static NSUserDefaults *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        defaults = [[NSUserDefaults alloc] initWithSuiteName:kSuiteName];
    });
    return defaults;
}

static NSString *FuTodayKey(void) {
    static NSDateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.dateFormat = @"yyyy-MM-dd";
    });
    return [fmt stringFromDate:[NSDate date]];
}

@implementation FudaiConfig

+ (instancetype)shared {
    static FudaiConfig *cfg;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cfg = [[FudaiConfig alloc] init];
        [cfg registerDefaults];
        [cfg reload];
    });
    return cfg;
}

- (void)registerDefaults {
    NSDictionary *d = @{
        kMaster: @NO,
        kPatrolMode: @(FuPatrolModeAutoJoin),   // v0.7.3 起默认即参与(旧安装见 reload 的一次性迁移)
        kSuperBagAuto: @YES,
        kNormalBagAuto: @YES,
        kCodeCommentAuto: @YES,
        kRedPacketAuto: @YES,
        kRoomPatrolAuto: @NO,
        kWinBanner: @YES,
        kDetectOnly: @NO,
        kPatrolMinSec: @15,
        kPatrolMaxSec: @45,
        kBagWaitSec: @8,
        kMaxJoinPerRoom: @3,
        kDailyJoinLimit: @0,
        kPatrolRoomTarget: @8,
        kTapDelayMs: @600,
        kCodeTemplate: @"口令",
        kShowFloatingBall: @YES,
        kTodayJoin: @0,
        kTodayWin: @0,
        kTodayRedpack: @0,
        kPatrolRooms: @0,
        kStatDay: @"",
    };
    [FuDefaults() registerDefaults:d];
}

- (void)reload {
    NSUserDefaults *d = FuDefaults();
    _master = [d boolForKey:kMaster];
    _patrolMode = (FuPatrolMode)[d integerForKey:kPatrolMode];
    // v0.7.3 一次性迁移:老版本把默认「仅检测」写进了偏好,表现就是"只检测不参与"。
    // 升级后第一次启动统一拉到「自动参与」;之后用户再手动选择就以用户为准。
    if (![d boolForKey:@"patrolModeMigratedV2"]) {
        _patrolMode = FuPatrolModeAutoJoin;
        [d setInteger:_patrolMode forKey:kPatrolMode];
        [d setBool:YES forKey:@"patrolModeMigratedV2"];
    }
    if (_patrolMode < FuPatrolModeDetectOnly || _patrolMode > FuPatrolModeFullPatrol) {
        _patrolMode = FuPatrolModeDetectOnly;
    }
    _superBagAuto = [d boolForKey:kSuperBagAuto];
    _normalBagAuto = [d boolForKey:kNormalBagAuto];
    _codeCommentAuto = [d boolForKey:kCodeCommentAuto];
    _redPacketAuto = [d boolForKey:kRedPacketAuto];
    _roomPatrolAuto = [d boolForKey:kRoomPatrolAuto];
    _winBanner = [d boolForKey:kWinBanner];
    _detectOnly = [d boolForKey:kDetectOnly];

    _patrolMinSec = [d integerForKey:kPatrolMinSec];
    _patrolMaxSec = [d integerForKey:kPatrolMaxSec];
    _bagWaitSec = [d integerForKey:kBagWaitSec];
    _maxJoinPerRoom = [d integerForKey:kMaxJoinPerRoom];
    _dailyJoinLimit = [d integerForKey:kDailyJoinLimit];
    _patrolRoomTarget = [d integerForKey:kPatrolRoomTarget];
    _tapDelayMs = [d integerForKey:kTapDelayMs];
    _codeTemplate = [d stringForKey:kCodeTemplate] ?: @"口令";
    _showFloatingBall = [d boolForKey:kShowFloatingBall];

    _todayJoin = [d integerForKey:kTodayJoin];
    _todayWin = [d integerForKey:kTodayWin];
    _todayRedpack = [d integerForKey:kTodayRedpack];
    _patrolRooms = [d integerForKey:kPatrolRooms];
    _statDay = [d stringForKey:kStatDay] ?: @"";

    if (_patrolMinSec < 5) _patrolMinSec = 5;
    if (_patrolMaxSec < _patrolMinSec) _patrolMaxSec = _patrolMinSec;
    if (_bagWaitSec < 2) _bagWaitSec = 2;
    if (_maxJoinPerRoom < 1) _maxJoinPerRoom = 1;
    if (_tapDelayMs < 100) _tapDelayMs = 100;

    [self refreshDayIfNeeded];
}

- (void)save {
    NSUserDefaults *d = FuDefaults();
    [d setBool:_master forKey:kMaster];
    [d setInteger:_patrolMode forKey:kPatrolMode];
    [d setBool:_superBagAuto forKey:kSuperBagAuto];
    [d setBool:_normalBagAuto forKey:kNormalBagAuto];
    [d setBool:_codeCommentAuto forKey:kCodeCommentAuto];
    [d setBool:_redPacketAuto forKey:kRedPacketAuto];
    [d setBool:_roomPatrolAuto forKey:kRoomPatrolAuto];
    [d setBool:_winBanner forKey:kWinBanner];
    [d setBool:_detectOnly forKey:kDetectOnly];
    [d setInteger:_patrolMinSec forKey:kPatrolMinSec];
    [d setInteger:_patrolMaxSec forKey:kPatrolMaxSec];
    [d setInteger:_bagWaitSec forKey:kBagWaitSec];
    [d setInteger:_maxJoinPerRoom forKey:kMaxJoinPerRoom];
    [d setInteger:_dailyJoinLimit forKey:kDailyJoinLimit];
    [d setInteger:_patrolRoomTarget forKey:kPatrolRoomTarget];
    [d setInteger:_tapDelayMs forKey:kTapDelayMs];
    [d setObject:(_codeTemplate ?: @"口令") forKey:kCodeTemplate];
    [d setBool:_showFloatingBall forKey:kShowFloatingBall];
    [d setInteger:_todayJoin forKey:kTodayJoin];
    [d setInteger:_todayWin forKey:kTodayWin];
    [d setInteger:_todayRedpack forKey:kTodayRedpack];
    [d setInteger:_patrolRooms forKey:kPatrolRooms];
    [d setObject:(_statDay ?: @"") forKey:kStatDay];
    // 抖音进程被强杀时 CFPreferences 有延迟落盘风险,这里显式同步
    [d synchronize];
}

#pragma mark - 日切与统计

- (void)refreshDayIfNeeded {
    NSString *today = FuTodayKey();
    if (_statDay.length && [_statDay isEqualToString:today]) return;
    _statDay = today;
    _todayJoin = 0;
    _todayWin = 0;
    _todayRedpack = 0;
    _patrolRooms = 0;
    [self save];
}

- (void)bumpJoin {
    [self refreshDayIfNeeded];
    _todayJoin += 1;
    [self save];
}

- (void)bumpRedpack {
    [self refreshDayIfNeeded];
    _todayRedpack += 1;
    [self save];
}

- (void)bumpWin {
    [self refreshDayIfNeeded];
    _todayWin += 1;
    [self save];
}

- (void)bumpRoom {
    [self refreshDayIfNeeded];
    _patrolRooms += 1;
    [self save];
}

- (void)resetToday {
    _statDay = FuTodayKey();
    _todayJoin = 0;
    _todayWin = 0;
    _todayRedpack = 0;
    _patrolRooms = 0;
    [self save];
}

- (UIColor *)accentColor {
    return [UIColor colorWithRed:1.00 green:0.18 blue:0.36 alpha:1.0];  // 福袋粉
}

@end

#pragma mark - 日志(环形,最多 400 行)

#define FU_LOG_CAP 400

static NSMutableArray<NSString *> *FuLogStore(void) {
    static NSMutableArray *arr;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ arr = [NSMutableArray array]; });
    return arr;
}

static NSLock *FuLogLock(void) {
    static NSLock *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [[NSLock alloc] init]; });
    return lock;
}

static NSDateFormatter *FuStampFormatter(void) {
    static NSDateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.dateFormat = @"HH:mm:ss";
    });
    return fmt;
}

void FuLog(NSString *fmt, ...) {
    if (!fmt) return;
    va_list ap;
    va_start(ap, fmt);
    NSString *body = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    if (!body) return;

    NSLock *lock = FuLogLock();
    [lock lock];
    // formatter 复用;放在锁内,跨线程调用也安全
    NSString *line = [NSString stringWithFormat:@"[%@] %@",
                      [FuStampFormatter() stringFromDate:[NSDate date]], body];
    NSMutableArray *store = FuLogStore();
    [store addObject:line];
    while (store.count > FU_LOG_CAP) [store removeObjectAtIndex:0];
    [lock unlock];

    NSLog(@"[Fudai] %@", body);
}

void FuLogClear(void) {
    NSLock *lock = FuLogLock();
    [lock lock];
    [FuLogStore() removeAllObjects];
    [lock unlock];
}

NSArray<NSString *> *FuLogLines(void) {
    NSLock *lock = FuLogLock();
    [lock lock];
    NSArray *copy = [FuLogStore() copy];
    [lock unlock];
    return copy ?: @[];
}

NSString *FuLogSnapshot(void) {
    NSArray<NSString *> *lines = FuLogLines();
    if (!lines.count) return @"(暂无日志)";
    return [lines componentsJoinedByString:@"\n"];
}
