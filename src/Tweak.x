//
//  Tweak.x
//  抖音福袋助手 —— hook 入口
//  目标: 抖音 40.7.0 (com.ss.iphone.ugc.Aweme), 主二进制 AwemeCore.framework
//
//  注入面尽量窄:福袋参与/口令/切台全部走视图层级自动化(FudaiScan),
//  这里只做两件事:
//    ① 设置页注入面板入口(新/旧两套设置体系都挂,仅设置首页)
//    ② App 启动完成后拉起引擎与悬浮球
//
//  设置页类名取自 40.7.0 实测(AWESettingPageBaseController / AWEGeneralSettingViewController
//  是新旧两套; AWESettingsTableViewController 是 40.7.0 起的 DUX 自定义导航栏版本)。
//

#import "FudaiConfig.h"
#import "FudaiEngine.h"
#import "FudaiPanel.h"
#import "FudaiUI.h"
#import <UIKit/UIKit.h>

#pragma mark - 设置页入口

static const NSInteger kFudaiEntryTag = 209528;

static void FudaiAddSettingEntry(UIViewController *vc) {
    @try {
        if (!vc.navigationItem) return;
        if (vc.navigationItem.rightBarButtonItem) return;
        UINavigationController *nav = vc.navigationController;
        if (nav && nav.viewControllers.count > 1) return;
        UIBarButtonItem *item = [[UIBarButtonItem alloc]
            initWithImage:FuSymbol(@"gift.fill", 17)
                    style:UIBarButtonItemStylePlain
                   target:[FudaiPanel shared]
                   action:@selector(spOpenFromSettings)];
        item.tintColor = FuPink();
        vc.navigationItem.rightBarButtonItem = item;
    } @catch (NSException *e) {
        NSLog(@"[Fudai] 设置页入口注入失败:%@", e);
    }
}

// 40.7.0 设置首页用 DUX 自定义导航栏,rightBarButtonItem 不渲染:
// 兜底注入右下角悬浮按钮,不依赖任何导航栏 API。
static void FudaiAddFloatingEntry(UIViewController *vc) {
    @try {
        if (!vc.isViewLoaded || !vc.view.window) return;
        if ([vc.view viewWithTag:kFudaiEntryTag]) return;
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.tag = kFudaiEntryTag;
        [btn setImage:FuSymbol(@"gift.fill", 17) forState:UIControlStateNormal];
        btn.tintColor = [UIColor whiteColor];
        btn.backgroundColor = FuPink();
        btn.layer.cornerRadius = 17.0;
        btn.layer.cornerCurve = kCACornerCurveContinuous;
        btn.translatesAutoresizingMaskIntoConstraints = NO;
        [vc.view addSubview:btn];
        [NSLayoutConstraint activateConstraints:@[
            [btn.widthAnchor constraintEqualToConstant:34],
            [btn.heightAnchor constraintEqualToConstant:34],
            [btn.trailingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
            [btn.bottomAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.bottomAnchor constant:-20],
        ]];
        [btn addTarget:[FudaiPanel shared]
                action:@selector(spOpenFromSettings)
      forControlEvents:UIControlEventTouchUpInside];
    } @catch (NSException *e) {
        NSLog(@"[Fudai] 设置页悬浮入口注入失败:%@", e);
    }
}

%hook AWESettingPageBaseController

- (void)viewDidLoad {
    %orig;
    FudaiAddSettingEntry((UIViewController *)self);
}

%end

%hook AWEGeneralSettingViewController

- (void)viewDidLoad {
    %orig;
    FudaiAddSettingEntry((UIViewController *)self);
}

%end

%hook AWESettingsTableViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    FudaiAddSettingEntry((UIViewController *)self);
    FudaiAddFloatingEntry((UIViewController *)self);
}

%end

#pragma mark - 启动

// 引擎/面板都自带幂等保护,重复调用安全:
// 正常时机(DidFinishLaunching 后 1.2s)拉起一次,再加一条 3s 兜底,
// 覆盖「插件注入晚于 App 启动通知」的场景(relaxin 下偶发)。
static void FudaiBootstrap(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[FudaiEngine shared] start];
        [[FudaiPanel shared] setup];
    });
}

static void FudaiInit(void) {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (![bundleID isEqualToString:@"com.ss.iphone.ugc.Aweme"]) return;

        [[FudaiConfig shared] reload];
        FuLog(@"注入成功:抖音 %@ (%@) · 插件 v%@", bundleID, FUDAI_BUILD, FUDAI_VER);

        FudaiBootstrap();

        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:^(NSNotification *note) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [[FudaiEngine shared] start];
                [[FudaiPanel shared] setup];
            });
        }];
    }
}

%ctor {
    FudaiInit();
}
