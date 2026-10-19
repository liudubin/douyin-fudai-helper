//
//  FudaiScan.h
//  视图层级武器库:窗口/顶层 VC 探测、关键词取视图、点按、口令提取、评论注入、切台
//
//  设计取向:全部走公开 UIKit 语义(递归取视图 + target-action / accessibilityActivate),
//  不依赖抖音私有 API,版本升级不会因方法签名变化而崩;找不到就返回 NO,由引擎降级。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "FudaiConfig.h"

#ifndef FudaiScan
#define FudaiScan   Fu4
#endif

/// 插件自有 UI(面板/悬浮球/横幅)的保留 tag 区间。
/// 面板开着时,自家文案(「评论口令自动发送」「口令已发送:xxx」日志等)
/// 会被扫描器当成直播间文本,进而误抽口令/误判中奖;walkFrom 会整棵跳过这个区间的子树。
extern const NSInteger FudaiUITagMin;
extern const NSInteger FudaiUITagMax;
extern BOOL FuIsOwnChrome(UIView *view);

@interface FudaiScan : NSObject

#pragma mark - 环境

/// keyWindow(iOS13+ 多 scene,遍历所有 window 取 isKeyWindow)
+ (UIWindow *)keyWindow;

/// 当前顶层控制器(穿透 presentedViewController / 导航栈 / tab)
+ (UIViewController *)topViewController;

/// 顶层 VC 的类名链(自身 → 父类,最多 4 层),用于直播间判定与日志
+ (NSString *)topViewControllerClassChain;

/// 疑似身处抖音直播间(类名链含 Live/Room,或层级里出现直播间专属视图类)
+ (BOOL)looksLikeLiveRoom;

#pragma mark - 视图检索

/// 递归匹配文本(标题/label/占位/无障碍标签)包含任一关键词的视图;limit<=0 表示不限
+ (NSArray<UIView *> *)viewsMatching:(NSArray<NSString *> *)keywords limit:(NSInteger)limit;

/// 当前窗口可见文本快照(去重,限 limit 条)
+ (NSString *)joinedTextsLimit:(NSInteger)limit;

/// 是否还有匹配关键词的可见视图
+ (BOOL)hasVisibleViewMatching:(NSArray<NSString *> *)keywords;

#pragma mark - 交互

/// 点按:优先最近的 UIControl(target-action),其次 accessibilityActivate
+ (BOOL)tap:(UIView *)view;

/// 找到并点按第一个匹配关键词的可交互视图
+ (BOOL)tapFirstMatching:(NSArray<NSString *> *)keywords;

/// 从可见文本里抽口令(形如「口令:8888」),抽不到返回 nil
+ (NSString *)extractCode;

/// 把文字灌进直播间评论输入框并发送(失败返回 NO)
+ (BOOL)injectComment:(NSString *)text;

/// 切到下一个直播(inertia 滚动信息流);失败返回 NO
+ (BOOL)switchToNextRoom;

#pragma mark - 文本提取

/// 视图自身承载的文本(label.text / button title / 输入框文本 / 无障碍标签)
+ (NSString *)textOfView:(UIView *)view;

@end
