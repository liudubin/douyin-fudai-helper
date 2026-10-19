//
//  FudaiProbe.m
//

#import "FudaiProbe.h"
#import <objc/runtime.h>

@interface FudaiProbe ()
@property (strong, nonatomic, readwrite) FudaiProbeResult *result;
@end

static const NSUInteger kTopLimit = 60;

#pragma mark - 关键词族

static NSArray<NSString *> *FuBagKeywords(void) {
    return @[@"chest", @"treasure", @"luckybag", @"fudai", @"lottery",
             @"redpacket", @"welfare", @"prize", @"jackpot"];
}

static NSArray<NSString *> *FuLiveKeywords(void) {
    return @[@"htslive", @"ieslive", @"liveroom", @"liveaudience", @"liveroom"];
}

static NSArray<NSString *> *FuCommentKeywords(void) {
    return @[@"livecomment", @"danmaku", @"sendcomment", @"commentinput", @"barrage"];
}

/// 40.7.0 二进制 ObjC 元数据实测存在(见 docs/class-probe-evidence.md)
static NSArray<NSString *> *FuVerifiedSeeds(void) {
    return @[@"HTSLiveChestInfo",
             @"HTSLiveChestOpenedInfo",
             @"HTSLiveChestOpenedInfo_WinningUser",
             @"HTSLiveChestTask",
             @"HTSLiveWaitChestOpenInfo",
             @"HTSLiveChestCardInfo",
             @"HTSLiveRedpackActivityInfo",
             @"HTSLivePreviewPromotionSyncData_LuckyBag",
             @"AWEIMCodeGenLuckyBagPrizeModel"];
}

#pragma mark - 结果

@implementation FudaiProbeResult

- (NSString *)statusLine {
    if (self.note.length) return self.note;
    return @"类名探测中…";
}

- (NSString *)reportText {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"进程 ObjC 类总数: %lu", (unsigned long)self.classTotal]];
    [lines addObject:[NSString stringWithFormat:@"福袋族命中: %lu   直播族命中: %lu   评论族命中: %lu",
                      (unsigned long)self.bagHits, (unsigned long)self.liveHits, (unsigned long)self.commentHits]];
    if (self.seedPresent.count) {
        [lines addObject:[NSString stringWithFormat:@"实测种子命中(%lu): %@",
                          (unsigned long)self.seedPresent.count,
                          [self.seedPresent componentsJoinedByString:@", "]]];
    }
    if (self.seedMissing.count) {
        [lines addObject:[NSString stringWithFormat:@"实测种子缺失(%lu): %@",
                          (unsigned long)self.seedMissing.count,
                          [self.seedMissing componentsJoinedByString:@", "]]];
    }
    if (self.bagTop.count) {
        [lines addObject:@"福袋族候选:"];
        for (NSString *item in self.bagTop) [lines addObject:[@"  " stringByAppendingString:item]];
    }
    if (self.liveTop.count) {
        [lines addObject:@"直播族候选:"];
        for (NSString *item in self.liveTop) [lines addObject:[@"  " stringByAppendingString:item]];
    }
    if (self.commentTop.count) {
        [lines addObject:@"评论族候选:"];
        for (NSString *item in self.commentTop) [lines addObject:[@"  " stringByAppendingString:item]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

@end

#pragma mark - 探测器

@implementation FudaiProbe

+ (instancetype)shared {
    static FudaiProbe *probe;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ probe = [[FudaiProbe alloc] init]; });
    return probe;
}

- (FudaiProbeResult *)result {
    if (!_result) {
        _result = [[FudaiProbeResult alloc] init];
        _result.note = @"类名探测中…";
    }
    return _result;
}

- (void)runAsync {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self run];
    });
}

static BOOL FuNameHasKeyword(NSString *lowerName, NSArray<NSString *> *keywords) {
    for (NSString *key in keywords) {
        if ([lowerName rangeOfString:key].location != NSNotFound) return YES;
    }
    return NO;
}

- (void)run {
    NSDate *start = [NSDate date];
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) {
        self.result.note = @"探测失败:类表为空";
        return;
    }
    Class *classes = (Class *)malloc(sizeof(Class) * (size_t)count);
    if (!classes) {
        self.result.note = @"探测失败:内存不足";
        return;
    }
    count = objc_getClassList(classes, count);

    NSMutableArray<NSDictionary *> *bag = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *live = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *comment = [NSMutableArray array];
    NSMutableSet<NSString *> *present = [NSMutableSet set];

    NSArray<NSString *> *bagKeys = FuBagKeywords();
    NSArray<NSString *> *liveKeys = FuLiveKeywords();
    NSArray<NSString *> *commentKeys = FuCommentKeywords();

    for (int i = 0; i < count; i++) {
        Class cls = classes[i];
        if (!cls) continue;
        const char *name = class_getName(cls);
        if (!name) continue;
        NSString *className = [NSString stringWithUTF8String:name];
        if (!className.length) continue;
        NSString *lower = className.lowercaseString;

        BOOL isBag = FuNameHasKeyword(lower, bagKeys);
        BOOL isLive = FuNameHasKeyword(lower, liveKeys);
        BOOL isComment = FuNameHasKeyword(lower, commentKeys);
        if (!isBag && !isLive && !isComment) continue;

        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        if (methods) free(methods);

        NSDictionary *entry = @{@"name": className, @"methods": @(methodCount)};
        if (isBag) [bag addObject:entry];
        if (isLive) [live addObject:entry];
        if (isComment) [comment addObject:entry];
        [present addObject:className];
    }
    free(classes);

    NSArray<NSDictionary *> *(^sorted)(NSArray<NSDictionary *> *) = ^NSArray<NSDictionary *> *(NSArray<NSDictionary *> *list) {
        return [list sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            NSInteger ma = [a[@"methods"] integerValue];
            NSInteger mb = [b[@"methods"] integerValue];
            if (ma == mb) return [a[@"name"] compare:b[@"name"]];
            return ma > mb ? NSOrderedAscending : NSOrderedDescending;
        }];
    };
    NSArray<NSString *> *(^flatten)(NSArray<NSDictionary *> *) = ^NSArray<NSString *> *(NSArray<NSDictionary *> *list) {
        NSMutableArray<NSString *> *out = [NSMutableArray array];
        for (NSDictionary *entry in list) {
            [out addObject:[NSString stringWithFormat:@"%@ (%@)", entry[@"name"], entry[@"methods"]]];
            if (out.count >= kTopLimit) break;
        }
        return out;
    };

    NSMutableArray<NSString *> *seedPresent = [NSMutableArray array];
    NSMutableArray<NSString *> *seedMissing = [NSMutableArray array];
    for (NSString *seed in FuVerifiedSeeds()) {
        if ([present containsObject:seed]) [seedPresent addObject:seed];
        else [seedMissing addObject:seed];
    }

    FudaiProbeResult *res = [[FudaiProbeResult alloc] init];
    res.classTotal = (NSUInteger)count;
    res.bagHits = bag.count;
    res.liveHits = live.count;
    res.commentHits = comment.count;
    res.bagTop = flatten(sorted(bag));
    res.liveTop = flatten(sorted(live));
    res.commentTop = flatten(sorted(comment));
    res.seedPresent = seedPresent;
    res.seedMissing = seedMissing;
    res.stamp = [NSDate date];
    res.note = [NSString stringWithFormat:@"已探测 %lu 个福袋候选 · %lu 个直播候选",
                (unsigned long)res.bagHits, (unsigned long)res.liveHits];
    _result = res;

    NSTimeInterval cost = [[NSDate date] timeIntervalSinceDate:start];
    FuLog(@"类名探测完成: 类 %lu / 福袋 %lu / 直播 %lu / 评论 %lu,耗时 %.0fms",
          (unsigned long)res.classTotal, (unsigned long)res.bagHits,
          (unsigned long)res.liveHits, (unsigned long)res.commentHits, cost * 1000.0);
    if (res.seedMissing.count) {
        FuLog(@"版本提示:%lu 个实测种子类缺失,可能不是 40.7.0 或元数据被裁剪",
              (unsigned long)res.seedMissing.count);
    }
}

@end
