//
//  FudaiUI.m
//

#import "FudaiUI.h"
#import "FudaiScan.h"

#pragma mark - 颜色

UIColor *FuPink(void) {
    return [[FudaiConfig shared] accentColor];
}

UIColor *FuWhite(CGFloat alpha) {
    return [UIColor colorWithWhite:1.0 alpha:alpha];
}

UIColor *FuGold(void) {
    return [UIColor colorWithRed:1.00 green:0.80 blue:0.24 alpha:1.0];
}

UIColor *FuGreen(void) {
    return [UIColor colorWithRed:0.35 green:0.92 blue:0.66 alpha:1.0];
}

UIColor *FuCardBG(void) {
    return [UIColor colorWithWhite:1.0 alpha:0.07];
}

UIColor *FuCardBorder(void) {
    return [UIColor colorWithWhite:1.0 alpha:0.08];
}

UIFont *FuFont(CGFloat size, UIFontWeight weight) {
    UIFont *font = [UIFont systemFontOfSize:size weight:weight];
    if (font) return font;
    return [UIFont boldSystemFontOfSize:size];
}

UILabel *FuLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *label = [[UILabel alloc] init];
    // 横向压缩/吸附都降到低优先级:任何文案都不许顶破滚动区的宽度锁
    [label setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                            forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentHuggingPriority:UILayoutPriorityDefaultLow
                              forAxis:UILayoutConstraintAxisHorizontal];
    label.text = text;
    label.font = FuFont(size, weight);
    label.textColor = color ?: FuWhite(0.92);
    label.numberOfLines = 0;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

UIImage *FuSymbol(NSString *name, CGFloat pointSize) {
    if (!name.length) return nil;
    UIImageSymbolConfiguration *conf = [UIImageSymbolConfiguration configurationWithPointSize:pointSize
                                                                                    weight:UIImageSymbolWeightSemibold];
    UIImage *image = [UIImage systemImageNamed:name withConfiguration:conf];
    if (!image) image = [UIImage systemImageNamed:name];
    return image;
}

UIView *FuSpacer(CGFloat height) {
    UIView *view = [[UIView alloc] init];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.backgroundColor = [UIColor clearColor];
    [view.heightAnchor constraintEqualToConstant:height].active = YES;
    return view;
}

static void FuPin(UIView *child, UIView *parent, UIEdgeInsets insets) {
    child.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [child.topAnchor constraintEqualToAnchor:parent.topAnchor constant:insets.top],
        [child.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor constant:-insets.bottom],
        [child.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor constant:insets.left],
        [child.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor constant:-insets.right],
    ]];
}

#pragma mark - 深色玻璃卡片

@interface FudaiGlassCard ()
@property (strong, nonatomic) UIView *blurClip;
@property (strong, nonatomic) UIVisualEffectView *blurView;
@property (strong, nonatomic, readwrite) UIView *content;
@end

@implementation FudaiGlassCard

+ (instancetype)cardWithPadding:(UIEdgeInsets)padding {
    FudaiGlassCard *card = [[FudaiGlassCard alloc] initWithFrame:CGRectZero];
    [card buildWithPadding:padding];
    return card;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.layer.cornerRadius = 16.0;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;
        self.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
        self.layer.borderColor = FuCardBorder().CGColor;
    }
    return self;
}

- (void)buildWithPadding:(UIEdgeInsets)padding {
    UIVisualEffectView *blur = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    blur.translatesAutoresizingMaskIntoConstraints = NO;
    blur.userInteractionEnabled = NO;
    [self addSubview:blur];
    FuPin(blur, self, UIEdgeInsetsZero);
    self.blurView = blur;

    UIView *tint = [[UIView alloc] init];
    tint.translatesAutoresizingMaskIntoConstraints = NO;
    tint.backgroundColor = FuCardBG();
    tint.userInteractionEnabled = NO;
    [self addSubview:tint];
    FuPin(tint, self, UIEdgeInsetsZero);

    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:content];
    FuPin(content, self, padding);
    self.content = content;
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    self.layer.cornerRadius = cornerRadius;
}

@end

#pragma mark - 开关行

@interface FudaiSwitchRow ()
@property (strong, nonatomic, readwrite) UISwitch *toggle;
@property (strong, nonatomic) UIView *badge;
@property (strong, nonatomic) UIImageView *badgeIcon;
@property (strong, nonatomic) UILabel *titleLabel;
@property (strong, nonatomic) UILabel *subtitleLabel;
@property (strong, nonatomic) UIColor *badgeTint;
@end

@implementation FudaiSwitchRow

+ (instancetype)rowWithIcon:(NSString *)symbol
                       tint:(UIColor *)tint
                      title:(NSString *)title
                   subtitle:(NSString *)subtitle {
    FudaiSwitchRow *row = [[FudaiSwitchRow alloc] initWithFrame:CGRectZero];
    [row buildIcon:symbol tint:tint title:title subtitle:subtitle];
    return row;
}

- (void)buildIcon:(NSString *)symbol tint:(UIColor *)tint title:(NSString *)title subtitle:(NSString *)subtitle {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = [UIColor clearColor];
    self.badgeTint = tint ?: FuPink();

    UIView *badge = [[UIView alloc] init];
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    badge.backgroundColor = tint ?: FuPink();
    badge.layer.cornerRadius = 10.0;
    badge.layer.cornerCurve = kCACornerCurveContinuous;
    [self addSubview:badge];
    self.badge = badge;

    UIImageView *icon = [[UIImageView alloc] initWithImage:FuSymbol(symbol, 15)];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tintColor = [UIColor whiteColor];
    [badge addSubview:icon];
    self.badgeIcon = icon;

    UILabel *titleLabel = FuLabel(title, 14.5, UIFontWeightSemibold, FuWhite(0.96));
    [self addSubview:titleLabel];
    self.titleLabel = titleLabel;

    UILabel *subtitleLabel = FuLabel(subtitle, 11.5, UIFontWeightRegular, FuWhite(0.52));
    subtitleLabel.numberOfLines = 0;
    [self addSubview:subtitleLabel];
    self.subtitleLabel = subtitleLabel;

    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.translatesAutoresizingMaskIntoConstraints = NO;
    toggle.onTintColor = FuPink();
    toggle.transform = CGAffineTransformMakeScale(0.82, 0.82);
    [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:toggle];
    self.toggle = toggle;

    [NSLayoutConstraint activateConstraints:@[
        [badge.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [badge.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [badge.widthAnchor constraintEqualToConstant:30],
        [badge.heightAnchor constraintEqualToConstant:30],

        [icon.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:16],
        [icon.heightAnchor constraintEqualToConstant:16],

        [titleLabel.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:10],
        [titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:9],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:toggle.leadingAnchor constant:-8],

        [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:2],
        [subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:toggle.leadingAnchor constant:-8],
        [subtitleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-9],

        [toggle.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [toggle.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
}

- (void)setOn:(BOOL)on {
    self.toggle.on = on;
}

- (BOOL)on {
    return self.toggle.isOn;
}

- (void)toggleChanged:(UISwitch *)sender {
    if (self.onToggle) self.onToggle(sender.isOn);
}

@end

#pragma mark - 分段控件

@interface FudaiSegmented ()
@property (strong, nonatomic) NSMutableArray<UIButton *> *buttons;
@property (strong, nonatomic) NSMutableArray<UIView *> *pills;
@end

@implementation FudaiSegmented

+ (instancetype)segmentedWithTitles:(NSArray<NSString *> *)titles {
    FudaiSegmented *seg = [[FudaiSegmented alloc] initWithFrame:CGRectZero];
    [seg buildWithTitles:titles];
    return seg;
}

- (void)buildWithTitles:(NSArray<NSString *> *)titles {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.buttons = [NSMutableArray array];
    self.pills = [NSMutableArray array];
    self.clipsToBounds = NO;

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.spacing = 6;
    [self addSubview:stack];
    FuPin(stack, self, UIEdgeInsetsZero);

    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        UIView *pill = [[UIView alloc] init];
        pill.translatesAutoresizingMaskIntoConstraints = NO;
        pill.backgroundColor = [UIColor clearColor];
        pill.layer.cornerRadius = 9.0;
        pill.layer.cornerCurve = kCACornerCurveContinuous;
        pill.userInteractionEnabled = NO;

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.translatesAutoresizingMaskIntoConstraints = NO;
        btn.tag = i;
        btn.titleLabel.font = FuFont(13.0, UIFontWeightSemibold);
    [btn.titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                                    forAxis:UILayoutConstraintAxisHorizontal];
        [btn setTitle:titles[(NSUInteger)i] forState:UIControlStateNormal];
        [btn setTitleColor:FuWhite(0.62) forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
        [btn addTarget:self action:@selector(segmentTapped:) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:btn];
        [self.buttons addObject:btn];

        [btn addSubview:pill];
        FuPin(pill, btn, UIEdgeInsetsZero);
        [btn sendSubviewToBack:pill];
        [self.pills addObject:pill];

        [btn.heightAnchor constraintEqualToConstant:30].active = YES;
    }
    [self applySelection:0];
}

- (void)segmentTapped:(UIButton *)sender {
    [self applySelection:sender.tag];
    if (self.onChange) self.onChange(sender.tag);
}

- (void)applySelection:(NSInteger)index {
    _selectedIndex = index;
    for (NSInteger i = 0; i < (NSInteger)self.buttons.count; i++) {
        UIButton *btn = self.buttons[(NSUInteger)i];
        UIView *pill = self.pills[(NSUInteger)i];
        BOOL on = (i == index);
        btn.selected = on;
        pill.backgroundColor = on ? FuPink() : [UIColor clearColor];
    }
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    if (selectedIndex < 0 || selectedIndex >= (NSInteger)self.buttons.count) return;
    [self applySelection:selectedIndex];
}

@end

#pragma mark - 统计条

@interface FudaiStatBar ()
@property (strong, nonatomic) UILabel *joinValue;
@property (strong, nonatomic) UILabel *winValue;
@property (strong, nonatomic) UILabel *roomValue;
@end

@implementation FudaiStatBar

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        UIStackView *stack = [[UIStackView alloc] init];
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.distribution = UIStackViewDistributionFillEqually;
        stack.alignment = UIStackViewAlignmentFill;
        [self addSubview:stack];
        FuPin(stack, self, UIEdgeInsetsMake(10, 0, 10, 0));

        self.joinValue = [self addColumnTo:stack title:@"今日参与" color:FuPink()];
        self.winValue = [self addColumnTo:stack title:@"今日中奖" color:FuGold()];
        self.roomValue = [self addColumnTo:stack title:@"巡逻房间" color:FuGreen()];
    }
    return self;
}

- (UILabel *)addColumnTo:(UIStackView *)stack title:(NSString *)title color:(UIColor *)color {
    UILabel *value = FuLabel(@"0", 16.0, UIFontWeightBold, color);
    value.textAlignment = NSTextAlignmentCenter;
    UILabel *caption = FuLabel(title, 10.5, UIFontWeightRegular, FuWhite(0.45));
    caption.textAlignment = NSTextAlignmentCenter;

    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[value, caption]];
    column.axis = UILayoutConstraintAxisVertical;
    column.spacing = 2;
    column.alignment = UIStackViewAlignmentFill;
    [stack addArrangedSubview:column];
    return value;
}

- (void)updateJoin:(NSInteger)join win:(NSInteger)win rooms:(NSInteger)rooms {
    self.joinValue.text = [NSString stringWithFormat:@"%ld", (long)join];
    self.winValue.text = [NSString stringWithFormat:@"%ld", (long)win];
    self.roomValue.text = [NSString stringWithFormat:@"%ld", (long)rooms];
}

@end

#pragma mark - 中奖横幅

static UIWindow *FuBannerWindow = nil;

@implementation FudaiBanner

+ (void)showWithText:(NSString *)text {
    if (!text.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        // 不能用 UIApplication.keyWindow:场景化后(iOS15+)常返回 nil,横幅就永远不弹
        UIWindow *host = [FudaiScan keyWindow];
        if (!host) return;
        if (!FuBannerWindow) {
            UIWindowScene *scene = host.windowScene;
            if (!scene) return;
            FuBannerWindow = [[UIWindow alloc] initWithWindowScene:scene];
            FuBannerWindow.windowLevel = UIWindowLevelAlert + 10;
            FuBannerWindow.backgroundColor = [UIColor clearColor];
            FuBannerWindow.rootViewController = [[UIViewController alloc] init];
            FuBannerWindow.rootViewController.view.tag = FudaiUITagMin;  // 横幅文本不进扫描器
        }
        FuBannerWindow.frame = host.bounds;
        FuBannerWindow.hidden = NO;
        UIViewController *root = FuBannerWindow.rootViewController;
        if (!root) return;

        [root.view.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

        UIView *banner = [[UIView alloc] init];
        banner.translatesAutoresizingMaskIntoConstraints = NO;
        banner.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.94];
        banner.layer.cornerRadius = 14.0;
        banner.layer.cornerCurve = kCACornerCurveContinuous;
        banner.layer.borderWidth = 0.8;
        banner.layer.borderColor = FuGold().CGColor;
        [root.view addSubview:banner];

        UILabel *label = FuLabel(text, 14.0, UIFontWeightSemibold, [UIColor whiteColor]);
        label.textAlignment = NSTextAlignmentCenter;
        [banner addSubview:label];

        [NSLayoutConstraint activateConstraints:@[
            [banner.centerXAnchor constraintEqualToAnchor:root.view.centerXAnchor],
            [banner.topAnchor constraintEqualToAnchor:root.view.safeAreaLayoutGuide.topAnchor constant:8],
            [banner.widthAnchor constraintLessThanOrEqualToAnchor:root.view.widthAnchor constant:-40],
            [label.topAnchor constraintEqualToAnchor:banner.topAnchor constant:10],
            [label.bottomAnchor constraintEqualToAnchor:banner.bottomAnchor constant:-10],
            [label.leadingAnchor constraintEqualToAnchor:banner.leadingAnchor constant:16],
            [label.trailingAnchor constraintEqualToAnchor:banner.trailingAnchor constant:-16],
        ]];

        banner.alpha = 0.0;
        banner.transform = CGAffineTransformMakeTranslation(0, -12);
        [UIView animateWithDuration:0.22 animations:^{
            banner.alpha = 1.0;
            banner.transform = CGAffineTransformIdentity;
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.25 animations:^{
                banner.alpha = 0.0;
                banner.transform = CGAffineTransformMakeTranslation(0, -12);
            } completion:^(BOOL finished) {
                [banner removeFromSuperview];
                FuBannerWindow.hidden = YES;
            }];
        });
    });
}

@end
