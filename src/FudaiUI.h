//
//  FudaiUI.h
//  面板视觉组件:深色玻璃卡片 / 开关行 / 分段控件 / 统计条 / 中奖横幅
//
//  截图基准:底部 sheet 全宽、深色磨砂、福袋粉强调色、
//  统计三列(今日参与 / 今日中奖 / 巡逻房间)、开关行左方形图标 + 主副标题 + 粉色开关。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "FudaiConfig.h"

#ifndef FudaiUI
#define FudaiUI         Fu5
#endif
#ifndef FudaiGlassCard
#define FudaiGlassCard  Fu6
#endif
#ifndef FudaiSwitchRow
#define FudaiSwitchRow  Fu7
#endif
#ifndef FudaiSegmented
#define FudaiSegmented  Fu8
#endif
#ifndef FudaiStatBar
#define FudaiStatBar    Fu9
#endif
#ifndef FudaiBanner
#define FudaiBanner     FuA
#endif

#pragma mark - 颜色/字体/小件

extern UIColor *FuPink(void);
extern UIColor *FuWhite(CGFloat alpha);
extern UIColor *FuGold(void);
extern UIColor *FuGreen(void);
extern UIColor *FuCardBG(void);
extern UIColor *FuCardBorder(void);
extern UIFont *FuFont(CGFloat size, UIFontWeight weight);
extern UILabel *FuLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color);
extern UIImage *FuSymbol(NSString *name, CGFloat pointSize);
extern UIView *FuSpacer(CGFloat height);

#pragma mark - 深色玻璃卡片

@interface FudaiGlassCard : UIView

/// 内容承载视图(四边内缩 padding 已由内部约束处理)
@property (strong, nonatomic, readonly) UIView *content;

+ (instancetype)cardWithPadding:(UIEdgeInsets)padding;
@property (assign, nonatomic) CGFloat cornerRadius;

@end

#pragma mark - 开关行

@interface FudaiSwitchRow : UIView

+ (instancetype)rowWithIcon:(NSString *)symbol
                       tint:(UIColor *)tint
                      title:(NSString *)title
                   subtitle:(NSString *)subtitle;

@property (copy, nonatomic) void (^onToggle)(BOOL on);
@property (assign, nonatomic) BOOL on;
@property (strong, nonatomic, readonly) UISwitch *toggle;

@end

#pragma mark - 分段控件

@interface FudaiSegmented : UIView

+ (instancetype)segmentedWithTitles:(NSArray<NSString *> *)titles;

@property (copy, nonatomic) void (^onChange)(NSInteger index);
@property (assign, nonatomic) NSInteger selectedIndex;

@end

#pragma mark - 统计条

@interface FudaiStatBar : UIView

- (void)updateJoin:(NSInteger)join win:(NSInteger)win rooms:(NSInteger)rooms pack:(NSInteger)pack;

@end

#pragma mark - 中奖横幅

@interface FudaiBanner : NSObject

+ (void)showWithText:(NSString *)text;

@end
