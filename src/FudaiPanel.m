//
//  FudaiPanel.m
//  悬浮球 + 底部 sheet 面板(主页 / 参数 / 日志)
//

#import "FudaiPanel.h"
#import "FudaiEngine.h"
#import "FudaiProbe.h"
#import "FudaiScan.h"
#import "FudaiUI.h"

static NSString *const kBallRatioX = @"panelBallRatioX";
static NSString *const kBallRatioY = @"panelBallRatioY";

/// 宿主 App(抖音)版本,面板副标题用;取不到时回落到插件版本
static NSString *FuHostAppVersion(void) {
    NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if ([ver isKindOfClass:[NSString class]] && ver.length) return ver;
    return FUDAI_VER;
}

static NSUserDefaults *FuPanelDefaults(void) {
    static NSUserDefaults *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.zhipu.fudaihelper"];
    });
    return defaults;
}

#pragma mark - 小件

static UILabel *FuSectionLabel(NSString *text) {
    UILabel *label = FuLabel(text, 11.0, UIFontWeightMedium, FuWhite(0.42));
    return label;
}

static UIButton *FuActionButton(NSString *title, UIImage *icon, UIColor *bg, UIColor *fg) {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.backgroundColor = bg;
    btn.layer.cornerRadius = 13.0;
    btn.layer.cornerCurve = kCACornerCurveContinuous;
    btn.titleLabel.font = FuFont(14.0, UIFontWeightSemibold);
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:fg forState:UIControlStateNormal];
    if (icon) [btn setImage:icon forState:UIControlStateNormal];
    btn.tintColor = fg;
    btn.imageEdgeInsets = UIEdgeInsetsMake(0, -4, 0, 4);
    [btn.heightAnchor constraintEqualToConstant:44].active = YES;
    return btn;
}

#pragma mark - 悬浮球

@interface FudaiFloatingBall : UIView
@property (copy, nonatomic) void (^onTap)(void);
@end

@interface FudaiFloatingBall ()
@property (strong, nonatomic) CAGradientLayer *gradient;
@property (strong, nonatomic) UIImageView *iconView;
@end

@implementation FudaiFloatingBall

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.94];
        self.layer.cornerRadius = frame.size.width / 2.0;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.35;
        self.layer.shadowRadius = 8.0;
        self.layer.shadowOffset = CGSizeMake(0, 3);
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = FuWhite(0.16).CGColor;

        _gradient = [CAGradientLayer layer];
        _gradient.colors = @[(id)FuPink().CGColor,
                             (id)[UIColor colorWithRed:1.0 green:0.42 blue:0.30 alpha:1.0].CGColor];
        _gradient.startPoint = CGPointMake(0, 0);
        _gradient.endPoint = CGPointMake(1, 1);
        _gradient.cornerRadius = frame.size.width / 2.0;
        _gradient.borderWidth = 0;
        [self.layer addSublayer:_gradient];

        _iconView = [[UIImageView alloc] initWithImage:FuSymbol(@"gift.fill", 20)];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.tintColor = [UIColor whiteColor];
        _iconView.userInteractionEnabled = NO;
        [self addSubview:_iconView];
        [NSLayoutConstraint activateConstraints:@[
            [_iconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:22],
            [_iconView.heightAnchor constraintEqualToConstant:22],
        ]];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.gradient.frame = self.bounds;
    self.gradient.cornerRadius = self.bounds.size.width / 2.0;
}

- (void)handleTap {
    if (self.onTap) self.onTap();
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIWindow *win = self.window;
    if (!win) return;
    CGPoint delta = [pan translationInView:win];
    CGPoint center = CGPointMake(self.center.x + delta.x, self.center.y + delta.y);
    CGFloat radius = self.bounds.size.width / 2.0;
    center.x = MAX(radius + 6, MIN(win.bounds.size.width - radius - 6, center.x));
    center.y = MAX(radius + 46, MIN(win.bounds.size.height - radius - 20, center.y));
    self.center = center;
    [pan setTranslation:CGPointZero inView:win];
    if (pan.state == UIGestureRecognizerStateEnded && win.bounds.size.width > 1) {
        [FuPanelDefaults() setDouble:(center.x / win.bounds.size.width) forKey:kBallRatioX];
        [FuPanelDefaults() setDouble:(center.y / win.bounds.size.height) forKey:kBallRatioY];
        [FuPanelDefaults() synchronize];
    }
}

@end

#pragma mark - 面板控制器

@interface FuPanelVC : UIViewController
@property (copy, nonatomic) void (^onRequestClose)(void);
@property (strong, nonatomic) UIView *card;
@property (strong, nonatomic) UILabel *statusLabel;
@property (strong, nonatomic) UILabel *engineLabel;
@property (strong, nonatomic) FudaiStatBar *statBar;
@property (strong, nonatomic) UIView *headerIcon;
@property (strong, nonatomic) FudaiSegmented *tabSeg;
@property (strong, nonatomic) FudaiSegmented *patrolSeg;
@property (strong, nonatomic) FudaiSwitchRow *masterRow;
@property (strong, nonatomic) FudaiSwitchRow *superRow;
@property (strong, nonatomic) FudaiSwitchRow *normalRow;
@property (strong, nonatomic) FudaiSwitchRow *codeRow;
@property (strong, nonatomic) FudaiSwitchRow *redpackRow;
@property (strong, nonatomic) FudaiSwitchRow *patrolRow;
@property (strong, nonatomic) FudaiSwitchRow *winRow;
@property (strong, nonatomic) FudaiSwitchRow *detectRow;
@property (strong, nonatomic) FudaiSwitchRow *ballRow;
@property (strong, nonatomic) UIScrollView *homeScroll;
@property (strong, nonatomic) UIScrollView *paramScroll;
@property (strong, nonatomic) UIScrollView *logScroll;
@property (strong, nonatomic) UITextView *logTextView;
@property (strong, nonatomic) NSMutableDictionary<NSString *, UITextField *> *paramFields;
@property (strong, nonatomic) UILabel *probeLabel;
@property (strong, nonatomic) UILabel *modeHintLabel;
@property (strong, nonatomic) UIToolbar *paramToolbar;
@property (weak, nonatomic) UITextField *editingField;
- (void)refreshUI;
- (void)refreshLog;
@end

@implementation FuPanelVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.tag = FudaiUITagMin + 1;   // 整个面板子树不进扫描器,自家文案不再污染口令/中奖识别
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(kbWillShow:)
                                                 name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(kbWillHide:)
                                                 name:UIKeyboardWillHideNotification object:nil];
    self.view.backgroundColor = [UIColor clearColor];
    self.paramFields = [NSMutableDictionary dictionary];
    [self buildDim];
    [self buildCard];
    [self refreshUI];
}

#pragma mark 构建

- (void)buildDim {
    UIView *dim = [[UIView alloc] init];
    dim.translatesAutoresizingMaskIntoConstraints = NO;
    dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.46];
    [self.view addSubview:dim];
    [NSLayoutConstraint activateConstraints:@[
        [dim.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [dim.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [dim.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [dim.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(closeTapped)];
    [dim addGestureRecognizer:tap];
}

- (void)buildCard {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor colorWithWhite:0.07 alpha:0.98];
    card.layer.cornerRadius = 22.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    card.clipsToBounds = YES;
    [self.view addSubview:card];
    self.card = card;

    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [card.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [card.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:0.88],
    ]];

    UIView *grabber = [[UIView alloc] init];
    grabber.translatesAutoresizingMaskIntoConstraints = NO;
    grabber.backgroundColor = FuWhite(0.22);
    grabber.layer.cornerRadius = 2.0;
    [card addSubview:grabber];
    [NSLayoutConstraint activateConstraints:@[
        [grabber.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [grabber.topAnchor constraintEqualToAnchor:card.topAnchor constant:8],
        [grabber.widthAnchor constraintEqualToConstant:38],
        [grabber.heightAnchor constraintEqualToConstant:4],
    ]];

    UIView *header = [self buildHeader];
    [card addSubview:header];

    FudaiSegmented *tabs = [FudaiSegmented segmentedWithTitles:@[@"主页", @"参数", @"日志"]];
    __weak typeof(self) weakSelf = self;
    tabs.onChange = ^(NSInteger index) {
        [weakSelf switchTab:index];
    };
    [card addSubview:tabs];
    self.tabSeg = tabs;

    UILabel *engine = FuLabel(@"引擎:类名探测中…", 10.5, UIFontWeightRegular, FuWhite(0.36));
    engine.textAlignment = NSTextAlignmentCenter;
    [card addSubview:engine];
    self.engineLabel = engine;

    UIView *pages = [[UIView alloc] init];
    pages.translatesAutoresizingMaskIntoConstraints = NO;
    pages.backgroundColor = [UIColor clearColor];
    [card addSubview:pages];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:grabber.bottomAnchor constant:10],
        [header.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [header.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],

        [tabs.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:12],
        [tabs.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [tabs.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],
        [tabs.heightAnchor constraintEqualToConstant:34],

        [pages.topAnchor constraintEqualToAnchor:tabs.bottomAnchor constant:10],
        [pages.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [pages.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],

        [engine.topAnchor constraintEqualToAnchor:pages.bottomAnchor constant:6],
        [engine.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [engine.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [engine.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8],
    ]];

    [self buildHomePageIn:pages];
    [self buildParamPageIn:pages];
    [self buildLogPageIn:pages];
    [self switchTab:0];
}

- (UIView *)buildHeader {
    UIView *header = [[UIView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *badge = [[UIView alloc] init];
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    badge.backgroundColor = FuPink();
    badge.layer.cornerRadius = 11.0;
    badge.layer.cornerCurve = kCACornerCurveContinuous;
    [header addSubview:badge];
    self.headerIcon = badge;

    UIImageView *icon = [[UIImageView alloc] initWithImage:FuSymbol(@"gift.fill", 18)];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = [UIColor whiteColor];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [badge addSubview:icon];

    UILabel *title = FuLabel(@"福袋助手", 20.0, UIFontWeightBold, FuWhite(0.98));
    [header addSubview:title];
    UILabel *subtitle = FuLabel([NSString stringWithFormat:@"抖音 %@ · 已适配极速版", FuHostAppVersion()],
                                11.5, UIFontWeightRegular, FuWhite(0.45));
    [header addSubview:subtitle];

    UILabel *status = FuLabel(@"● 运行中", 12.0, UIFontWeightMedium, FuGreen());
    status.textAlignment = NSTextAlignmentRight;
    [header addSubview:status];
    self.statusLabel = status;

    UIButton *minimize = [UIButton buttonWithType:UIButtonTypeSystem];
    minimize.translatesAutoresizingMaskIntoConstraints = NO;
    [minimize setTitle:@"—" forState:UIControlStateNormal];
    [minimize setTitleColor:FuWhite(0.55) forState:UIControlStateNormal];
    minimize.titleLabel.font = FuFont(17.0, UIFontWeightSemibold);
    [minimize addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:minimize];

    [NSLayoutConstraint activateConstraints:@[
        [badge.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [badge.topAnchor constraintEqualToAnchor:header.topAnchor],
        [badge.widthAnchor constraintEqualToConstant:38],
        [badge.heightAnchor constraintEqualToConstant:38],

        [icon.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:20],
        [icon.heightAnchor constraintEqualToConstant:20],

        [title.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:10],
        [title.topAnchor constraintEqualToAnchor:header.topAnchor constant:1],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:status.leadingAnchor constant:-8],

        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],
        [subtitle.bottomAnchor constraintEqualToAnchor:header.bottomAnchor],

        [minimize.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [minimize.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [minimize.widthAnchor constraintEqualToConstant:26],
        [minimize.heightAnchor constraintEqualToConstant:26],

        [status.trailingAnchor constraintEqualToAnchor:minimize.leadingAnchor constant:-8],
        [status.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
    ]];
    return header;
}

- (UIScrollView *)scrollWithStack:(UIStackView *)stack {
    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    scroll.showsVerticalScrollIndicator = NO;
    scroll.alwaysBounceHorizontal = NO;
    scroll.showsHorizontalScrollIndicator = NO;
    scroll.directionalLockEnabled = YES;   // 首个手势轴锁定,斜着滑也不横移
    scroll.contentInset = UIEdgeInsetsMake(0, 0, 12, 0);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    // 侧边 18pt 留白走布局边距;滚动区加横向 inset 会凭空多出可横拖区间,
    // 纵向滑动手指稍斜内容就左右荡(「面板上下滑内容左右晃」的根因)
    stack.layoutMargins = UIEdgeInsetsMake(0, 18, 0, 18);
    stack.layoutMarginsRelativeArrangement = YES;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-12],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
    ]];
    return scroll;
}

- (UIStackView *)makeStack {
    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.alignment = UIStackViewAlignmentFill;
    return stack;
}

- (void)buildHomePageIn:(UIView *)pages {
    UIStackView *stack = [self makeStack];
    UIScrollView *scroll = [self scrollWithStack:stack];
    scroll.contentInset = UIEdgeInsetsMake(0, 0, 12, 0);
    [pages addSubview:scroll];
    [self pinPage:scroll in:pages];
    self.homeScroll = scroll;

    FudaiGlassCard *statCard = [FudaiGlassCard cardWithPadding:UIEdgeInsetsMake(6, 6, 6, 6)];
    FudaiStatBar *stats = [[FudaiStatBar alloc] initWithFrame:CGRectZero];
    [statCard.content addSubview:stats];
    [NSLayoutConstraint activateConstraints:@[
        [stats.topAnchor constraintEqualToAnchor:statCard.content.topAnchor],
        [stats.bottomAnchor constraintEqualToAnchor:statCard.content.bottomAnchor],
        [stats.leadingAnchor constraintEqualToAnchor:statCard.content.leadingAnchor],
        [stats.trailingAnchor constraintEqualToAnchor:statCard.content.trailingAnchor],
    ]];
    self.statBar = stats;
    [stack addArrangedSubview:statCard];

    FudaiGlassCard *masterCard = [FudaiGlassCard cardWithPadding:UIEdgeInsetsMake(4, 14, 4, 14)];
    FudaiSwitchRow *master = [FudaiSwitchRow rowWithIcon:@"power" tint:FuPink()
                                                   title:@"福袋助手 · 总开关"
                                                subtitle:@"关闭后所有自动参与行为停止"];
    __weak typeof(self) weakSelf = self;
    master.onToggle = ^(BOOL on) {
        [weakSelf masterChanged:on];
    };
    [masterCard.content addSubview:master];
    [NSLayoutConstraint activateConstraints:@[
        [master.topAnchor constraintEqualToAnchor:masterCard.content.topAnchor],
        [master.bottomAnchor constraintEqualToAnchor:masterCard.content.bottomAnchor],
        [master.leadingAnchor constraintEqualToAnchor:masterCard.content.leadingAnchor],
        [master.trailingAnchor constraintEqualToAnchor:masterCard.content.trailingAnchor],
    ]];
    self.masterRow = master;
    [stack addArrangedSubview:masterCard];

    [stack addArrangedSubview:FuSectionLabel(@"巡逻模式")];
    FudaiSegmented *patrol = [FudaiSegmented segmentedWithTitles:@[@"仅检测", @"自动参与", @"全自动巡逻"]];
    patrol.onChange = ^(NSInteger index) {
        [weakSelf patrolModeChanged:index];
    };
    [stack addArrangedSubview:patrol];
    [patrol.heightAnchor constraintEqualToConstant:32].active = YES;
    self.patrolSeg = patrol;

    UILabel *modeHint = FuLabel(@"", 10.5, UIFontWeightRegular, FuWhite(0.40));
    modeHint.numberOfLines = 0;
    [stack addArrangedSubview:modeHint];
    self.modeHintLabel = modeHint;

    [stack addArrangedSubview:FuSectionLabel(@"功能开关")];

    self.superRow = [self addSwitchRowTo:stack icon:@"gift.fill" tint:FuPink()
                                   title:@"超级福袋 · 自动参与"
                                subtitle:@"金福袋(超级福袋)自动参与,含口令"];
    self.normalRow = [self addSwitchRowTo:stack icon:@"bag.fill"
                                     tint:[UIColor colorWithRed:1.0 green:0.70 blue:0.20 alpha:1.0]
                                    title:@"普通福袋 · 自动参与"
                                 subtitle:@"左上角普通福袋自动参与"];
    self.codeRow = [self addSwitchRowTo:stack icon:@"ellipsis.bubble.fill"
                                   tint:[UIColor colorWithRed:0.18 green:0.66 blue:1.0 alpha:1.0]
                                  title:@"评论口令自动发送"
                               subtitle:@"type=3 口令参与走评论 hook 发送"];
    self.redpackRow = [self addSwitchRowTo:stack icon:@"yensign.circle.fill"
                                      tint:[UIColor colorWithRed:1.0 green:0.42 blue:0.36 alpha:1.0]
                                     title:@"红包口令自动发送"
                                  subtitle:@"红包出现即抓口令并自动评论"];
    self.patrolRow = [self addSwitchRowTo:stack icon:@"arrow.triangle.2.circlepath"
                                     tint:[UIColor colorWithRed:0.07 green:0.84 blue:0.75 alpha:1.0]
                                    title:@"直播间自动巡逻"
                                 subtitle:@"无福袋时自动切台(15-45s)"];
    self.winRow = [self addSwitchRowTo:stack icon:@"bell.badge.fill"
                                  tint:[UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0]
                                 title:@"中奖横幅提醒"
                              subtitle:@"中奖时顶部弹出强提醒"];
    self.detectRow = [self addSwitchRowTo:stack icon:@"eye.fill"
                                     tint:[UIColor colorWithWhite:0.56 alpha:1.0]
                                    title:@"仅检测模式"
                                 subtitle:@"只检测不参与(灰度观察用)"];

    self.superRow.onToggle = ^(BOOL on) { [weakSelf featureChanged:@"super" on:on]; };
    self.normalRow.onToggle = ^(BOOL on) { [weakSelf featureChanged:@"normal" on:on]; };
    self.codeRow.onToggle = ^(BOOL on) { [weakSelf featureChanged:@"code" on:on]; };
    self.redpackRow.onToggle = ^(BOOL on) { [weakSelf featureChanged:@"redpack" on:on]; };
    self.patrolRow.onToggle = ^(BOOL on) { [weakSelf featureChanged:@"patrol" on:on]; };
    self.winRow.onToggle = ^(BOOL on) { [weakSelf featureChanged:@"win" on:on]; };
    self.detectRow.onToggle = ^(BOOL on) { [weakSelf featureChanged:@"detect" on:on]; };

    [stack addArrangedSubview:FuSpacer(2)];

    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.spacing = 10;
    actions.distribution = UIStackViewDistributionFillEqually;
    UIButton *copyBtn = FuActionButton(@"复制诊断", FuSymbol(@"doc.on.doc.fill", 13),
                                       FuPink(), [UIColor whiteColor]);
    [copyBtn addTarget:self action:@selector(copyTapped) forControlEvents:UIControlEventTouchUpInside];
    UIButton *hideBtn = FuActionButton(@"隐藏面板", FuSymbol(@"chevron.down", 13),
                                       FuWhite(0.10), FuWhite(0.86));
    [hideBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [actions addArrangedSubview:copyBtn];
    [actions addArrangedSubview:hideBtn];
    [stack addArrangedSubview:actions];
}

- (FudaiSwitchRow *)addSwitchRowTo:(UIStackView *)stack
                              icon:(NSString *)icon
                              tint:(UIColor *)tint
                             title:(NSString *)title
                          subtitle:(NSString *)subtitle {
    FudaiGlassCard *card = [FudaiGlassCard cardWithPadding:UIEdgeInsetsMake(4, 14, 4, 14)];
    FudaiSwitchRow *row = [FudaiSwitchRow rowWithIcon:icon tint:tint title:title subtitle:subtitle];
    [card.content addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:card.content.topAnchor],
        [row.bottomAnchor constraintEqualToAnchor:card.content.bottomAnchor],
        [row.leadingAnchor constraintEqualToAnchor:card.content.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:card.content.trailingAnchor],
    ]];
    [stack addArrangedSubview:card];
    return row;
}

- (void)buildParamPageIn:(UIView *)pages {
    UIStackView *stack = [self makeStack];
    UIScrollView *scroll = [self scrollWithStack:stack];
    scroll.contentInset = UIEdgeInsetsMake(0, 0, 12, 0);
    [pages addSubview:scroll];
    [self pinPage:scroll in:pages];
    self.paramScroll = scroll;

    FudaiConfig *cfg = [FudaiConfig shared];

    [stack addArrangedSubview:FuSectionLabel(@"巡逻与判定")];
    [stack addArrangedSubview:[self paramRow:@"无福袋判定下限(秒)" key:@"patrolMinSec"
                                       value:[NSString stringWithFormat:@"%ld", (long)cfg.patrolMinSec] numeric:YES]];
    [stack addArrangedSubview:[self paramRow:@"无福袋判定上限(秒)" key:@"patrolMaxSec"
                                       value:[NSString stringWithFormat:@"%ld", (long)cfg.patrolMaxSec] numeric:YES]];
    [stack addArrangedSubview:[self paramRow:@"进房等福袋宽限(秒)" key:@"bagWaitSec"
                                       value:[NSString stringWithFormat:@"%ld", (long)cfg.bagWaitSec] numeric:YES]];
    [stack addArrangedSubview:[self paramRow:@"点按后稳定等待(毫秒)" key:@"tapDelayMs"
                                       value:[NSString stringWithFormat:@"%ld", (long)cfg.tapDelayMs] numeric:YES]];

    [stack addArrangedSubview:FuSectionLabel(@"参与上限")];
    [stack addArrangedSubview:[self paramRow:@"单房间最多参与" key:@"maxJoinPerRoom"
                                       value:[NSString stringWithFormat:@"%ld", (long)cfg.maxJoinPerRoom] numeric:YES]];
    [stack addArrangedSubview:[self paramRow:@"今日参与上限(0=不限)" key:@"dailyJoinLimit"
                                       value:[NSString stringWithFormat:@"%ld", (long)cfg.dailyJoinLimit] numeric:YES]];
    [stack addArrangedSubview:[self paramRow:@"巡逻房间目标(0=不限)" key:@"patrolRoomTarget"
                                       value:[NSString stringWithFormat:@"%ld", (long)cfg.patrolRoomTarget] numeric:YES]];
    [stack addArrangedSubview:[self paramRow:@"口令兜底模板" key:@"codeTemplate"
                                       value:cfg.codeTemplate ?: @"口令" numeric:NO]];

    [stack addArrangedSubview:FuSectionLabel(@"面板")];
    FudaiGlassCard *ballCard = [FudaiGlassCard cardWithPadding:UIEdgeInsetsMake(4, 14, 4, 14)];
    FudaiSwitchRow *ballRow = [FudaiSwitchRow rowWithIcon:@"circle.grid.2x2.fill" tint:FuPink()
                                                    title:@"显示悬浮球"
                                                 subtitle:@"关闭后只能从设置页入口打开面板"];
    ballRow.onToggle = ^(BOOL on) {
        [FudaiConfig shared].showFloatingBall = on;
        [[FudaiConfig shared] save];
        [[FudaiPanel shared] attachIfNeeded];
    };
    [ballCard.content addSubview:ballRow];
    [NSLayoutConstraint activateConstraints:@[
        [ballRow.topAnchor constraintEqualToAnchor:ballCard.content.topAnchor],
        [ballRow.bottomAnchor constraintEqualToAnchor:ballCard.content.bottomAnchor],
        [ballRow.leadingAnchor constraintEqualToAnchor:ballCard.content.leadingAnchor],
        [ballRow.trailingAnchor constraintEqualToAnchor:ballCard.content.trailingAnchor],
    ]];
    self.ballRow = ballRow;
    [stack addArrangedSubview:ballCard];

    [stack addArrangedSubview:FuSectionLabel(@"引擎")];
    UILabel *probe = FuLabel(@"等待探测…", 11.0, UIFontWeightRegular, FuWhite(0.62));
    FudaiGlassCard *probeCard = [FudaiGlassCard cardWithPadding:UIEdgeInsetsMake(12, 14, 12, 14)];
    [probeCard.content addSubview:probe];
    [NSLayoutConstraint activateConstraints:@[
        [probe.topAnchor constraintEqualToAnchor:probeCard.content.topAnchor],
        [probe.bottomAnchor constraintEqualToAnchor:probeCard.content.bottomAnchor],
        [probe.leadingAnchor constraintEqualToAnchor:probeCard.content.leadingAnchor],
        [probe.trailingAnchor constraintEqualToAnchor:probeCard.content.trailingAnchor],
    ]];
    self.probeLabel = probe;
    [stack addArrangedSubview:probeCard];

    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.spacing = 10;
    actions.distribution = UIStackViewDistributionFillEqually;
    UIButton *probeBtn = FuActionButton(@"立即探测", FuSymbol(@"waveform.path.ecg", 13),
                                        FuWhite(0.10), FuWhite(0.90));
    [probeBtn addTarget:self action:@selector(probeTapped) forControlEvents:UIControlEventTouchUpInside];
    UIButton *resetBtn = FuActionButton(@"清空今日统计", FuSymbol(@"arrow.counterclockwise", 13),
                                        FuWhite(0.10), FuWhite(0.90));
    [resetBtn addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [actions addArrangedSubview:probeBtn];
    [actions addArrangedSubview:resetBtn];
    [stack addArrangedSubview:actions];
}

- (UIView *)paramRow:(NSString *)title key:(NSString *)key value:(NSString *)value numeric:(BOOL)numeric {
    FudaiGlassCard *card = [FudaiGlassCard cardWithPadding:UIEdgeInsetsMake(11, 14, 11, 14)];
    UILabel *label = FuLabel(title, 13.0, UIFontWeightMedium, FuWhite(0.88));
    UITextField *field = [[UITextField alloc] init];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.text = value;
    field.textAlignment = NSTextAlignmentRight;
    field.textColor = FuWhite(0.98);
    field.font = FuFont(13.0, UIFontWeightSemibold);
    field.keyboardType = numeric ? UIKeyboardTypeNumberPad : UIKeyboardTypeDefault;
    field.returnKeyType = UIReturnKeyDone;
    field.accessibilityIdentifier = key;
    field.inputAccessoryView = [self paramToolbar];   // 数字键盘没有回车键,给个「完成」
    [field addTarget:self action:@selector(paramFieldEndEditing:) forControlEvents:UIControlEventEditingDidEnd];
    [field addTarget:self action:@selector(paramFieldBegan:) forControlEvents:UIControlEventEditingDidBegin];
    [card.content addSubview:label];
    [card.content addSubview:field];
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:card.content.topAnchor],
        [label.bottomAnchor constraintEqualToAnchor:card.content.bottomAnchor],
        [label.leadingAnchor constraintEqualToAnchor:card.content.leadingAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:field.leadingAnchor constant:-10],

        [field.centerYAnchor constraintEqualToAnchor:card.content.centerYAnchor],
        [field.trailingAnchor constraintEqualToAnchor:card.content.trailingAnchor],
        [field.widthAnchor constraintGreaterThanOrEqualToConstant:88],
    ]];
    self.paramFields[key] = field;
    return card;
}

- (void)buildLogPageIn:(UIView *)pages {
    UIStackView *stack = [self makeStack];
    UIScrollView *scroll = [self scrollWithStack:stack];
    scroll.contentInset = UIEdgeInsetsMake(0, 0, 12, 0);
    [pages addSubview:scroll];
    [self pinPage:scroll in:pages];
    self.logScroll = scroll;

    UITextView *textView = [[UITextView alloc] init];
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    textView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.05];
    textView.textColor = FuWhite(0.86);
    textView.font = [UIFont fontWithName:@"Menlo" size:10.5] ?: FuFont(10.5, UIFontWeightRegular);
    textView.editable = NO;
    textView.textContainerInset = UIEdgeInsetsMake(10, 10, 10, 10);
    textView.layer.cornerRadius = 14.0;
    textView.layer.cornerCurve = kCACornerCurveContinuous;
    textView.text = FuLogSnapshot();
    [textView.heightAnchor constraintEqualToConstant:400].active = YES;
    self.logTextView = textView;
    [stack addArrangedSubview:textView];

    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.spacing = 10;
    actions.distribution = UIStackViewDistributionFillEqually;
    UIButton *refreshBtn = FuActionButton(@"刷新日志", FuSymbol(@"arrow.clockwise", 13),
                                          FuWhite(0.10), FuWhite(0.90));
    [refreshBtn addTarget:self action:@selector(refreshLogTapped) forControlEvents:UIControlEventTouchUpInside];
    UIButton *clearBtn = FuActionButton(@"清空日志", FuSymbol(@"trash.fill", 13),
                                        FuWhite(0.10), FuWhite(0.90));
    [clearBtn addTarget:self action:@selector(clearLogTapped) forControlEvents:UIControlEventTouchUpInside];
    [actions addArrangedSubview:refreshBtn];
    [actions addArrangedSubview:clearBtn];
    [stack addArrangedSubview:actions];
}

- (void)pinPage:(UIView *)page in:(UIView *)container {
    [NSLayoutConstraint activateConstraints:@[
        [page.topAnchor constraintEqualToAnchor:container.topAnchor],
        [page.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [page.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [page.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
    ]];
}

#pragma mark 交互

- (void)switchTab:(NSInteger)index {
    self.homeScroll.hidden = (index != 0);
    self.paramScroll.hidden = (index != 1);
    self.logScroll.hidden = (index != 2);
    if (self.tabSeg.selectedIndex != index) self.tabSeg.selectedIndex = index;
    if (index == 2) [self refreshLog];
}

- (void)closeTapped {
    if (self.editingField) {
        [self.editingField resignFirstResponder];
        self.editingField = nil;
        return;
    }
    if (self.onRequestClose) self.onRequestClose();
}

- (void)masterChanged:(BOOL)on {
    FudaiConfig *cfg = [FudaiConfig shared];
    cfg.master = on;
    [cfg save];
    [[FudaiEngine shared] notifyConfigChanged];
    FuLog(@"总开关 → %@", on ? @"开" : @"关");
    [self refreshUI];
}

- (void)patrolModeChanged:(NSInteger)index {
    FudaiConfig *cfg = [FudaiConfig shared];
    cfg.patrolMode = (FuPatrolMode)index;
    [cfg save];
    [[FudaiEngine shared] notifyConfigChanged];
    FuLog(@"巡逻模式 → %@", FuPatrolModeName(cfg.patrolMode));
    [self refreshUI];
}

- (void)featureChanged:(NSString *)flag on:(BOOL)on {
    FudaiConfig *cfg = [FudaiConfig shared];
    if ([flag isEqualToString:@"super"]) cfg.superBagAuto = on;
    else if ([flag isEqualToString:@"normal"]) cfg.normalBagAuto = on;
    else if ([flag isEqualToString:@"code"]) cfg.codeCommentAuto = on;
    else if ([flag isEqualToString:@"redpack"]) cfg.redPacketAuto = on;
    else if ([flag isEqualToString:@"patrol"]) cfg.roomPatrolAuto = on;
    else if ([flag isEqualToString:@"win"]) cfg.winBanner = on;
    else if ([flag isEqualToString:@"detect"]) cfg.detectOnly = on;
    [cfg save];
    [[FudaiEngine shared] notifyConfigChanged];
    FuLog(@"功能开关 %@ → %@", flag, on ? @"开" : @"关");
}

- (void)paramFieldBegan:(UITextField *)field {
    self.editingField = field;
}

- (void)paramDoneTapped {
    [self.view endEditing:YES];
}

- (UIToolbar *)paramToolbar {
    if (_paramToolbar) return _paramToolbar;
    UIToolbar *bar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    bar.barStyle = UIBarStyleBlack;
    bar.translucent = YES;
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                          target:nil action:NULL];
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                          target:self action:@selector(paramDoneTapped)];
    bar.items = @[flex, done];
    [bar sizeToFit];
    _paramToolbar = bar;
    return bar;
}

// 键盘弹起时把卡片抬起来(顶部留 16pt),盖不住的部分用 contentInset 滚进去
- (void)kbWillShow:(NSNotification *)note {
    NSValue *v = note.userInfo[UIKeyboardFrameEndUserInfoKey];
    if (!v) return;
    CGRect kb = [v CGRectValue];
    CGFloat hidden = MAX(0.0, CGRectGetMaxY(self.view.bounds) - kb.origin.y);
    if (hidden <= 1.0) return;
    CGFloat lift = MIN(hidden, MAX(0.0, self.card.frame.origin.y - 16.0));
    CGFloat remain = hidden - lift;
    __weak typeof(self) weakSelf = self;
    [UIView animateWithDuration:0.28 animations:^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.card.transform = CGAffineTransformMakeTranslation(0, -lift);
        strongSelf.paramScroll.contentInset = UIEdgeInsetsMake(0, 0, remain + 24, 0);
        strongSelf.homeScroll.contentInset = UIEdgeInsetsMake(0, 0, remain + 24, 0);
    } completion:^(BOOL finished) {
        UITextField *field = weakSelf.editingField;
        if (field && field.superview) {
            [weakSelf.paramScroll scrollRectToVisible:[field convertRect:field.bounds toView:weakSelf.paramScroll]
                                              animated:YES];
        }
    }];
}

- (void)kbWillHide:(NSNotification *)note {
    (void)note;
    __weak typeof(self) weakSelf = self;
    [UIView animateWithDuration:0.24 animations:^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.card.transform = CGAffineTransformIdentity;
        strongSelf.paramScroll.contentInset = UIEdgeInsetsZero;
        strongSelf.homeScroll.contentInset = UIEdgeInsetsZero;
    }];
}

- (void)paramFieldEndEditing:(UITextField *)field {
    NSString *key = field.accessibilityIdentifier;
    if (!key.length) return;
    FudaiConfig *cfg = [FudaiConfig shared];
    NSString *text = field.text ?: @"";
    NSInteger value = text.integerValue;

    if ([key isEqualToString:@"patrolMinSec"]) cfg.patrolMinSec = MAX(5, value);
    else if ([key isEqualToString:@"patrolMaxSec"]) cfg.patrolMaxSec = MAX(cfg.patrolMinSec, value);
    else if ([key isEqualToString:@"bagWaitSec"]) cfg.bagWaitSec = MAX(2, value);
    else if ([key isEqualToString:@"tapDelayMs"]) cfg.tapDelayMs = MAX(100, value);
    else if ([key isEqualToString:@"maxJoinPerRoom"]) cfg.maxJoinPerRoom = MAX(1, value);
    else if ([key isEqualToString:@"dailyJoinLimit"]) cfg.dailyJoinLimit = MAX(0, value);
    else if ([key isEqualToString:@"patrolRoomTarget"]) cfg.patrolRoomTarget = MAX(0, value);
    else if ([key isEqualToString:@"codeTemplate"]) cfg.codeTemplate = text.length ? text : @"口令";

    [cfg save];
    cfg = [FudaiConfig shared];
    [[FudaiEngine shared] notifyConfigChanged];
    FuLog(@"参数 %@ → %@", key, text);
    [self refreshUI];
}

- (void)copyTapped {
    [[FudaiPanel shared] copyDiagnostic];
}

- (void)probeTapped {
    [[FudaiEngine shared] probeNow];
    [FudaiBanner showWithText:@"类名探测已开始"];
}

- (void)resetTapped {
    [[FudaiEngine shared] resetToday];
    [self refreshUI];
    [FudaiBanner showWithText:@"今日统计已清空"];
}

- (void)refreshLogTapped {
    [self refreshLog];
}

- (void)clearLogTapped {
    FuLogClear();
    [self refreshLog];
}

#pragma mark 刷新

- (void)refreshLog {
    self.logTextView.text = FuLogSnapshot();
    if (self.logTextView.text.length) {
        NSRange range = NSMakeRange(self.logTextView.text.length - 1, 1);
        [self.logTextView scrollRangeToVisible:range];
    }
}

- (void)refreshUI {
    FudaiConfig *cfg = [FudaiConfig shared];
    [self.statBar updateJoin:cfg.todayJoin win:cfg.todayWin rooms:cfg.patrolRooms pack:cfg.todayRedpack];
    self.masterRow.on = cfg.master;
    self.superRow.on = cfg.superBagAuto;
    self.normalRow.on = cfg.normalBagAuto;
    self.codeRow.on = cfg.codeCommentAuto;
    self.redpackRow.on = cfg.redPacketAuto;
    self.patrolRow.on = cfg.roomPatrolAuto;
    self.winRow.on = cfg.winBanner;
    self.detectRow.on = cfg.detectOnly;
    if (self.ballRow) self.ballRow.on = cfg.showFloatingBall;
    if (self.patrolSeg.selectedIndex != (NSInteger)cfg.patrolMode) {
        self.patrolSeg.selectedIndex = (NSInteger)cfg.patrolMode;
    }
    static NSDictionary<NSNumber *, NSString *> *hints;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        hints = @{
            @(FuPatrolModeDetectOnly) : @"当前仅检测:识别福袋与中奖,不点按、不发评论、不切台",
            @(FuPatrolModeAutoJoin)   : @"自动参与:留在当前直播间,检测到福袋即自动参与",
            @(FuPatrolModeFullPatrol) : @"全自动巡逻:无福袋时按 15-45s 随机时长自动切台",
        };
    });
    self.modeHintLabel.text = hints[@(cfg.patrolMode)] ?: @"";

    FudaiEngine *engine = [FudaiEngine shared];
    NSString *summary = [engine stateSummary];
    self.statusLabel.text = [NSString stringWithFormat:@"● %@", summary];
    self.statusLabel.textColor = cfg.master ? FuGreen() : FuWhite(0.4);
    self.engineLabel.text = [NSString stringWithFormat:@"引擎:%@", [engine engineLine]];

    FudaiProbeResult *probe = [FudaiProbe shared].result;
    if (self.probeLabel) {
        self.probeLabel.text = [NSString stringWithFormat:@"%@\n福袋 %lu · 直播 %lu · 评论 %lu",
                                [probe statusLine],
                                (unsigned long)probe.bagHits,
                                (unsigned long)probe.liveHits,
                                (unsigned long)probe.commentHits];
    }

    NSDictionary<NSString *, UITextField *> *fields = [self.paramFields copy];
    for (NSString *key in fields) {
        UITextField *field = fields[key];
        if (field.isFirstResponder) continue;
        if ([key isEqualToString:@"patrolMinSec"]) field.text = [NSString stringWithFormat:@"%ld", (long)cfg.patrolMinSec];
        else if ([key isEqualToString:@"patrolMaxSec"]) field.text = [NSString stringWithFormat:@"%ld", (long)cfg.patrolMaxSec];
        else if ([key isEqualToString:@"bagWaitSec"]) field.text = [NSString stringWithFormat:@"%ld", (long)cfg.bagWaitSec];
        else if ([key isEqualToString:@"tapDelayMs"]) field.text = [NSString stringWithFormat:@"%ld", (long)cfg.tapDelayMs];
        else if ([key isEqualToString:@"maxJoinPerRoom"]) field.text = [NSString stringWithFormat:@"%ld", (long)cfg.maxJoinPerRoom];
        else if ([key isEqualToString:@"dailyJoinLimit"]) field.text = [NSString stringWithFormat:@"%ld", (long)cfg.dailyJoinLimit];
        else if ([key isEqualToString:@"patrolRoomTarget"]) field.text = [NSString stringWithFormat:@"%ld", (long)cfg.patrolRoomTarget];
        else if ([key isEqualToString:@"codeTemplate"]) field.text = cfg.codeTemplate ?: @"口令";
    }
    if (!self.logScroll.hidden) [self refreshLog];
}

@end

#pragma mark - 对外入口

@interface FudaiPanel ()
- (void)refreshVisiblePanel;
@end

static UIViewController *FuActivePanel = nil;

@implementation FudaiPanel {
    FudaiFloatingBall *_ball;
    NSTimer *_attachTimer;
}

+ (instancetype)shared {
    static FudaiPanel *panel;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ panel = [[FudaiPanel alloc] init]; });
    return panel;
}

- (void)setup {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    __weak typeof(self) weakSelf = self;
    [FudaiEngine shared].onStateChange = ^{
        [weakSelf refreshVisiblePanel];
    };
    [self attachIfNeeded];
    if (!_attachTimer) {
        _attachTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *t) {
            [weakSelf attachIfNeeded];
        }];
        [[NSRunLoop mainRunLoop] addTimer:_attachTimer forMode:NSRunLoopCommonModes];
    }
    FuLog(@"面板就绪");
}

- (void)refreshVisiblePanel {
    if (!FuActivePanel) return;
    if ([FuActivePanel isKindOfClass:[FuPanelVC class]]) {
        [(FuPanelVC *)FuActivePanel refreshUI];
    }
}

- (void)attachIfNeeded {
    FudaiConfig *cfg = [FudaiConfig shared];
    if (!cfg.showFloatingBall) {
        if (_ball) {
            [_ball removeFromSuperview];
            _ball = nil;
        }
        return;
    }
    UIWindow *win = [FudaiScan keyWindow];
    if (!win) return;
    if (_ball && _ball.superview == win) return;
    if (!_ball) {
        CGFloat size = 54.0;
        FudaiFloatingBall *ball = [[FudaiFloatingBall alloc] initWithFrame:CGRectMake(0, 0, size, size)];
        ball.tag = FudaiUITagMin + 2;   // 悬浮球文案不进扫描器
        __weak typeof(self) weakSelf = self;
        ball.onTap = ^{
            [weakSelf present];
        };
        _ball = ball;
    }
    [_ball removeFromSuperview];
    [win addSubview:_ball];
    [win bringSubviewToFront:_ball];

    double ratioX = [FuPanelDefaults() doubleForKey:kBallRatioX];
    double ratioY = [FuPanelDefaults() doubleForKey:kBallRatioY];
    if (ratioX <= 0.01 || ratioX >= 0.99) ratioX = 0.86;
    if (ratioY <= 0.01 || ratioY >= 0.99) ratioY = 0.62;
    CGFloat size = _ball.bounds.size.width > 1 ? _ball.bounds.size.width : 54.0;
    _ball.frame = CGRectMake(win.bounds.size.width * ratioX - size / 2.0,
                             win.bounds.size.height * ratioY - size / 2.0,
                             size, size);
}

- (void)present {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 面板被系统/用户从别处收走时 presentingViewController 会变 nil,这里顺手清引用
        if (FuActivePanel && !FuActivePanel.presentingViewController) FuActivePanel = nil;
        if (FuActivePanel) return;
        UIViewController *host = [FudaiScan topViewController];
        if (!host) {
            FuLog(@"打开面板失败:没有可用宿主控制器");
            return;
        }
        FuPanelVC *vc = [[FuPanelVC alloc] init];
        vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
        vc.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
        __weak typeof(self) weakSelf = self;
        vc.onRequestClose = ^{
            [weakSelf dismiss];
        };
        FuActivePanel = vc;
        [host presentViewController:vc animated:YES completion:^{
            FuLog(@"面板已打开");
        }];
    });
}

- (void)dismiss {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!FuActivePanel) return;
        UIViewController *vc = FuActivePanel;
        FuActivePanel = nil;
        [vc dismissViewControllerAnimated:YES completion:^{
            FuLog(@"面板已收起");
        }];
    });
}

- (void)spOpenFromSettings {
    [self present];
}

- (void)copyDiagnostic {
    NSString *text = [[FudaiEngine shared] diagnosticText];
    [UIPasteboard generalPasteboard].string = text;
    FuLog(@"诊断已复制(%lu 字节)", (unsigned long)text.length);
    [FudaiBanner showWithText:@"诊断已复制到剪贴板"];
}

@end
