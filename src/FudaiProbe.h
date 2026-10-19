//
//  FudaiProbe.h
//  类名探测引擎(面板底部「引擎:类名探测中」一行即由本模块提供)
//
//  为什么需要探测:抖音不提供稳定的福袋公开接口,且各版本类名会漂移。
//  本模块在运行期遍历进程内全部 ObjC 类,按关键词族(福袋/直播/评论)匹配,
//  统计命中量与可用方法数,并把结果同时用于:
//    ① 面板「参数」页展示候选类与命中计数(灰度观察)
//    ② 诊断文本(复制诊断)
//    ③ 诊断与版本核对(实测种子类缺失时提示"可能不是该版本")
//
//  seeds 为本仓库对 40.7.0 二进制 ObjC 元数据实测确认存在的类名,
//  用于在 UI 上给出「该版本是否具备福袋能力」的确定性依据,不参与实际 hook。
//

#import <Foundation/Foundation.h>

#import "FudaiConfig.h"

#ifndef FudaiProbe
#define FudaiProbe          Fu3
#endif
#ifndef FudaiProbeResult
#define FudaiProbeResult    FuC
#endif

@interface FudaiProbeResult : NSObject

@property (assign, nonatomic) NSUInteger classTotal;      // 进程内 ObjC 类总数
@property (assign, nonatomic) NSUInteger bagHits;         // 福袋族命中总数
@property (assign, nonatomic) NSUInteger liveHits;        // 直播族命中总数
@property (assign, nonatomic) NSUInteger commentHits;     // 评论族命中总数
@property (copy, nonatomic) NSArray<NSString *> *bagTop;      // 命中最多的若干类("类名(methodCount)")
@property (copy, nonatomic) NSArray<NSString *> *liveTop;
@property (copy, nonatomic) NSArray<NSString *> *commentTop;
@property (copy, nonatomic) NSArray<NSString *> *seedPresent;  // 40.7.0 实测种子里当前存在的
@property (copy, nonatomic) NSArray<NSString *> *seedMissing;
@property (copy, nonatomic) NSString *note;               // "类名探测中…" / "已探测 N 个候选"
@property (strong, nonatomic) NSDate *stamp;

- (NSString *)statusLine;   // 面板底栏一行
- (NSString *)reportText;   // 参数页/诊断用多行文本

@end

@interface FudaiProbe : NSObject

+ (instancetype)shared;

@property (strong, nonatomic, readonly) FudaiProbeResult *result;

/// 后台队列跑一次(启动时调用,不阻塞主线程)
- (void)runAsync;

/// 同步扫描
- (void)run;

@end
