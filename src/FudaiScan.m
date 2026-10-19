//
//  FudaiScan.m
//

#import "FudaiScan.h"
#import <objc/runtime.h>

static const NSInteger kMaxWalkNodes = 8000;
static const NSInteger kMaxWalkDepth = 60;

const NSInteger FudaiUITagMin = 209530;
const NSInteger FudaiUITagMax = 209539;

BOOL FuIsOwnChrome(UIView *view) {
    return view.tag >= FudaiUITagMin && view.tag <= FudaiUITagMax;
}

@interface FudaiScan (Private)
+ (void)walkFrom:(UIView *)root block:(void (^)(UIView *view, NSInteger depth, BOOL *stop))block;
+ (BOOL)matches:(NSString *)text keywords:(NSArray<NSString *> *)keywords;
+ (NSArray<UIView *> *)editableViews;
+ (UIButton *)findSendControl;
+ (BOOL)tap:(UIView *)view atPoint:(CGPoint)point;
+ (NSArray<UIView *> *)rankCandidates:(NSArray<UIView *> *)candidates;
+ (NSInteger)scoreOfCandidate:(UIView *)v screenH:(CGFloat)H;
+ (BOOL)tapAccessibilityElementMatching:(NSArray<NSString *> *)keywords;
+ (BOOL)tapScreenPoint:(CGPoint)screenPoint;
@end

#pragma mark - 文本提取

@implementation FudaiScan

+ (NSString *)textOfView:(UIView *)view {
    if (!view) return nil;
    NSString *text = nil;
    if ([view isKindOfClass:[UILabel class]]) {
        text = ((UILabel *)view).text;
    } else if ([view isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)view;
        text = [btn titleForState:UIControlStateNormal];
        if (!text.length) text = btn.currentTitle;
    } else if ([view isKindOfClass:[UITextField class]]) {
        UITextField *field = (UITextField *)view;
        text = field.text.length ? field.text : field.placeholder;
    } else if ([view isKindOfClass:[UITextView class]]) {
        text = ((UITextView *)view).text;
    }
    if (!text.length) {
        NSString *label = view.accessibilityLabel;
        if ([label isKindOfClass:[NSString class]] && label.length) text = label;
    }
    return text.length ? text : nil;
}

#pragma mark - 遍历

+ (void)walkFrom:(UIView *)root block:(void (^)(UIView *view, NSInteger depth, BOOL *stop))block {
    if (!root || !block) return;
    if (FuIsOwnChrome(root)) return;
    NSMutableArray<NSArray *> *stack = [NSMutableArray array];
    [stack addObject:@[root, @0]];
    NSInteger visited = 0;
    BOOL stop = NO;
    while (stack.count) {
        NSArray *item = stack.lastObject;
        [stack removeLastObject];
        UIView *view = item[0];
        NSInteger depth = [item[1] integerValue];
        visited += 1;
        if (visited > kMaxWalkNodes || stop) break;
        block(view, depth, &stop);
        if (stop) break;
        if (depth >= kMaxWalkDepth) continue;
        NSArray<UIView *> *subviews = view.subviews;
        for (NSInteger i = (NSInteger)subviews.count - 1; i >= 0; i--) {
            UIView *sub = subviews[(NSUInteger)i];
            if (sub.hidden || sub.alpha < 0.01) continue;
            if (FuIsOwnChrome(sub)) continue;   // 插件面板/悬浮球/横幅整棵跳过
            [stack addObject:@[sub, @(depth + 1)]];
        }
    }
}

+ (BOOL)matches:(NSString *)text keywords:(NSArray<NSString *> *)keywords {
    if (!text.length || !keywords.count) return NO;
    for (NSString *key in keywords) {
        if (!key.length) continue;
        if ([text rangeOfString:key options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

#pragma mark - 环境

+ (UIWindow *)keyWindow {
    UIApplication *app = [UIApplication sharedApplication];
    UIWindow *fallback = nil;
    for (UIWindow *win in app.windows) {
        if (!win.isHidden && win.alpha > 0.01) {
            if (win.isKeyWindow) return win;
            if (!fallback) fallback = win;
        }
    }
    if (fallback) return fallback;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *win in ((UIWindowScene *)scene).windows) {
                if (win.isKeyWindow) return win;
            }
        }
    }
    return app.windows.firstObject;
}

+ (UIViewController *)topViewController {
    UIViewController *vc = [self keyWindow].rootViewController;
    NSInteger guard = 0;
    while (vc && guard < 20) {
        guard += 1;
        if (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) {
            vc = vc.presentedViewController;
            continue;
        }
        if ([vc isKindOfClass:[UINavigationController class]]) {
            UIViewController *top = ((UINavigationController *)vc).topViewController;
            if (top) { vc = top; continue; }
        }
        if ([vc isKindOfClass:[UITabBarController class]]) {
            UIViewController *sel = ((UITabBarController *)vc).selectedViewController;
            if (sel) { vc = sel; continue; }
        }
        if ([vc isKindOfClass:[UISplitViewController class]]) {
            UIViewController *last = ((UISplitViewController *)vc).viewControllers.lastObject;
            if (last) { vc = last; continue; }
        }
        break;
    }
    return vc;
}

+ (NSString *)topViewControllerClassChain {
    UIViewController *vc = [self topViewController];
    if (!vc) return @"?";
    NSMutableArray<NSString *> *chain = [NSMutableArray array];
    Class cls = [vc class];
    for (NSInteger i = 0; i < 4 && cls; i++) {
        [chain addObject:NSStringFromClass(cls)];
        cls = class_getSuperclass(cls);
    }
    return [chain componentsJoinedByString:@" < "];
}

+ (BOOL)looksLikeLiveRoom {
    NSString *chain = [self topViewControllerClassChain];
    NSArray *roomKeys = @[@"Live", @"Room", @"HTS"];
    for (NSString *key in roomKeys) {
        if ([chain rangeOfString:key options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    // 类名不含 Live 时,再看层级里有没有直播间专属视图(悬挂福袋/礼物面板/观众列表)
    UIWindow *win = [self keyWindow];
    if (!win) return NO;
    __block BOOL hit = NO;
    [self walkFrom:win block:^(UIView *view, NSInteger depth, BOOL *stop) {
        NSString *cls = NSStringFromClass([view class]);
        if ([cls rangeOfString:@"LiveRoom" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [cls rangeOfString:@"HTSLive" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            hit = YES;
            *stop = YES;
        }
    }];
    return hit;
}

#pragma mark - 视图检索

+ (NSArray<UIView *> *)viewsMatching:(NSArray<NSString *> *)keywords limit:(NSInteger)limit {
    UIWindow *win = [self keyWindow];
    NSMutableArray<UIView *> *found = [NSMutableArray array];
    if (!win || !keywords.count) return found;
    [self walkFrom:win block:^(UIView *view, NSInteger depth, BOOL *stop) {
        NSString *text = [self textOfView:view];
        if (![self matches:text keywords:keywords]) return;
        if (view.bounds.size.width < 1 || view.bounds.size.height < 1) {
            // 文本节点常挂在 0 尺寸容器上,取其父视图作为点击目标
            UIView *parent = view.superview;
            if (parent && parent.bounds.size.width > 8 && parent.bounds.size.height > 8) {
                [found addObject:parent];
                return;
            }
        }
        [found addObject:view];
        if (limit > 0 && (NSInteger)found.count >= limit) *stop = YES;
    }];
    return found;
}

+ (BOOL)hasVisibleViewMatching:(NSArray<NSString *> *)keywords {
    return [self viewsMatching:keywords limit:1].count > 0;
}

+ (NSString *)joinedTextsLimit:(NSInteger)limit {
    UIWindow *win = [self keyWindow];
    if (!win) return @"";
    NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSet];
    [self walkFrom:win block:^(UIView *view, NSInteger depth, BOOL *stop) {
        NSString *text = [self textOfView:view];
        if (text.length > 0 && text.length < 60) [set addObject:text];
        if (limit > 0 && (NSInteger)set.count >= limit) *stop = YES;
    }];
    return [[set array] componentsJoinedByString:@" | "];
}

#pragma mark - 交互

// 合成触摸(最后兜底):福袋面板是 Lynx/H5 混合容器,既不是 UIControl、
// accessibilityActivate 也常常不响应,只能伪造 UITouch 走 UIApplication sendEvent。
// 越狱插件用私有字段没有审核问题,但字段名随版本漂移,所以整体 @try 包住,失败只记日志。
static BOOL FuSynthesizeTap(UIView *view, CGPoint point) {
    @try {
        UIWindow *win = view.window ?: [FudaiScan keyWindow];
        if (!win) return NO;
        CGPoint windowPoint = [view convertPoint:point toView:win];

        UITouch *touch = [[UITouch alloc] init];
        [touch setValue:[NSValue valueWithCGPoint:windowPoint] forKey:@"_tapLocation"];
        [touch setValue:[NSDate date] forKey:@"_timestamp"];
        [touch setValue:@(1) forKey:@"_tapCount"];
        [touch setValue:@(UITouchPhaseBegan) forKey:@"_phase"];
        [touch setValue:win forKey:@"_window"];
        [touch setValue:view forKey:@"_view"];
        [touch setValue:@[] forKey:@"_gestureRecognizers"];

        UIEvent *event = [[UIEvent alloc] init];
        NSMethodSignature *sig = [event methodSignatureForSelector:@selector(_addTouch:forDelayedDelivery:)];
        if (sig) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:event];
            [inv setSelector:@selector(_addTouch:forDelayedDelivery:)];
            id touchArg = touch;
            BOOL noDelivery = NO;
            [inv setArgument:&touchArg atIndex:2];
            [inv setArgument:&noDelivery atIndex:3];
            [inv invoke];
        } else {
            [event setValue:[NSSet setWithObject:touch] forKey:@"_touches"];
        }
        [[UIApplication sharedApplication] sendEvent:event];

        [touch setValue:@(UITouchPhaseEnded) forKey:@"_phase"];
        [touch setValue:[NSValue valueWithCGPoint:windowPoint] forKey:@"_tapLocation"];
        [[UIApplication sharedApplication] sendEvent:event];
        FuLog(@"已用合成触摸点按 %@ %@", NSStringFromClass([view class]),
              NSStringFromCGPoint(windowPoint));
        return YES;
    } @catch (NSException *e) {
        FuLog(@"合成触摸失败(%@),放弃", e.name);
        return NO;
    }
}

+ (BOOL)tap:(UIView *)view {
    if (!view) return NO;
    return [self tap:view
             atPoint:CGPointMake(CGRectGetMidX(view.bounds), CGRectGetMidY(view.bounds))];
}

+ (BOOL)tap:(UIView *)view atPoint:(CGPoint)point {
    if (!view) return NO;
    UIView *cursor = view;
    for (NSInteger i = 0; i < 6 && cursor; i++) {
        if ([cursor isKindOfClass:[UIControl class]] && cursor.isUserInteractionEnabled) {
            [(UIControl *)cursor sendActionsForControlEvents:UIControlEventTouchUpInside];
            return YES;
        }
        cursor = cursor.superview;
    }
    if ([view respondsToSelector:@selector(accessibilityActivate)] && view.accessibilityActivate) {
        return YES;
    }
    if ([view respondsToSelector:@selector(sendActionsForControlEvents:)]) {
        [(UIControl *)view sendActionsForControlEvents:UIControlEventTouchUpInside];
        return YES;
    }
    return FuSynthesizeTap(view, point);
}

// 候选打分:优先「是按钮」>「屏幕靠下」>「不是超大容器」。
// 参与按钮几乎总在面板底部且是 UIControl;而「参与规则」这类纯文本在顶部,得分低。
+ (NSInteger)scoreOfCandidate:(UIView *)v screenH:(CGFloat)H {
    NSInteger score = 0;
    UIView *cur = v;
    for (NSInteger i = 0; i < 6 && cur; i++) {
        if ([cur isKindOfClass:[UIControl class]]) { score += 1000; break; }
        cur = cur.superview;
    }
    if (!v.userInteractionEnabled) score -= 300;
    CGRect f = [v convertRect:v.bounds toView:nil];
    if (f.size.height > 0) score += (NSInteger)(f.origin.y / MAX(H, 1) * 200.0);
    if (f.size.width * f.size.height > 60000) score -= 150;   // 整块容器不是按钮
    return score;
}

+ (NSArray<UIView *> *)rankCandidates:(NSArray<UIView *> *)candidates {
    UIWindow *win = [self keyWindow];
    CGFloat H = win ? win.bounds.size.height : 800.0;
    return [candidates sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        NSInteger sa = [self scoreOfCandidate:a screenH:H];
        NSInteger sb = [self scoreOfCandidate:b screenH:H];
        if (sa != sb) return sa > sb ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];
}

// 无障碍元素兜底:福袋面板常是 Lynx/H5,文本不在 UILabel 里,
// 但 iOS 会把 web 内容暴露成 accessibilityElements(label + 屏幕坐标 frame)。
+ (BOOL)tapAccessibilityElementMatching:(NSArray<NSString *> *)keywords {
    UIWindow *win = [self keyWindow];
    if (!win) return NO;
    __block BOOL done = NO;
    [self walkFrom:win block:^(UIView *view, NSInteger depth, BOOL *stop) {
        if (done) { *stop = YES; return; }
        NSArray *elements = view.accessibilityElements;
        if (![elements isKindOfClass:[NSArray class]] || !elements.count) return;
        for (id el in elements) {
            NSString *label = [el accessibilityLabel];
            if (![self matches:label keywords:keywords]) continue;
            CGRect frame = [el accessibilityFrame];
            if (frame.size.width < 8 || frame.size.height < 8) continue;
            FuLog(@"无障碍元素命中「%@」,屏幕坐标 %@", label, NSStringFromCGRect(frame));
            if ([self tapScreenPoint:CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame))]) {
                done = YES;
                *stop = YES;
                return;
            }
        }
    }];
    return done;
}

// accessibilityFrame 是屏幕坐标;转窗口坐标后 hitTest 拿到真实视图再点
+ (BOOL)tapScreenPoint:(CGPoint)screenPoint {
    UIWindow *win = [self keyWindow];
    if (!win) return NO;
    CGPoint local = CGPointMake(screenPoint.x - win.frame.origin.x,
                                screenPoint.y - win.frame.origin.y);
    UIView *hit = [win hitTest:local withEvent:nil];
    if (!hit) return NO;
    return [self tap:hit atPoint:[hit convertPoint:local fromView:win]];
}

+ (BOOL)tapFirstMatching:(NSArray<NSString *> *)keywords {
    NSArray<UIView *> *candidates = [self viewsMatching:keywords limit:10];
    for (UIView *view in [self rankCandidates:candidates]) {
        if ([self tap:view]) return YES;
    }
    return [self tapAccessibilityElementMatching:keywords];
}

#pragma mark - 口令

+ (NSString *)extractCode {
    NSString *texts = [self joinedTextsLimit:220];
    if (!texts.length) return nil;
    NSError *err = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"口令[:：]?\\s*([^\\s，,。；;|]{2,16})"
                                                                          options:0
                                                                            error:&err];
    if (err || !regex) return nil;
    NSTextCheckingResult *match = [regex firstMatchInString:texts options:0 range:NSMakeRange(0, texts.length)];
    if (!match || match.numberOfRanges < 2) return nil;
    NSString *code = [texts substringWithRange:[match rangeAtIndex:1]];
    code = [code stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray *noise = @[@"参与", @"领取", @"开奖", @"点击", @"发送", @"评论", @"复制", @"输入", @"福袋"];
    for (NSString *bad in noise) {
        if ([code isEqualToString:bad]) return nil;
    }
    // 去掉常见的尾随修饰词
    for (NSString *suffix in @[@"参与", @"领取", @"即可"]) {
        if ([code hasSuffix:suffix] && code.length > suffix.length) {
            code = [code substringToIndex:code.length - suffix.length];
        }
    }
    return code.length >= 2 ? code : nil;
}

#pragma mark - 评论注入

+ (NSArray<UIView *> *)editableViews {
    UIWindow *win = [self keyWindow];
    NSMutableArray<UIView *> *result = [NSMutableArray array];
    if (!win) return result;
    [self walkFrom:win block:^(UIView *view, NSInteger depth, BOOL *stop) {
        if ([view isKindOfClass:[UITextField class]]) {
            UITextField *f = (UITextField *)view;
            if (f.isUserInteractionEnabled && !f.secureTextEntry) [result addObject:f];
        } else if ([view isKindOfClass:[UITextView class]]) {
            UITextView *t = (UITextView *)view;
            if (t.isEditable && t.isUserInteractionEnabled) [result addObject:t];
        }
    }];
    return result;
}

+ (BOOL)injectComment:(NSString *)text {
    if (!text.length) return NO;
    NSArray<UIView *> *editables = [self editableViews];
    if (!editables.count) {
        FuLog(@"评论注入失败:直播间没有可编辑输入框");
        return NO;
    }
    NSArray *preferredKeys = @[@"说点什么", @"评论", @"聊", @"发弹幕"];
    UIView *target = nil;
    for (UIView *view in editables) {
        NSString *hint = nil;
        if ([view isKindOfClass:[UITextField class]]) hint = ((UITextField *)view).placeholder;
        if (!hint.length) hint = view.accessibilityLabel;
        if ([self matches:hint keywords:preferredKeys]) { target = view; break; }
    }
    if (!target) target = editables.firstObject;

    if ([target isKindOfClass:[UITextField class]]) {
        UITextField *field = (UITextField *)target;
        field.text = text;
        [field sendActionsForControlEvents:UIControlEventEditingChanged];
        UIResponder *delegate = (UIResponder *)field.delegate;
        if ([delegate respondsToSelector:@selector(textFieldShouldReturn:)]) {
            [(id<UITextFieldDelegate>)field.delegate textFieldShouldReturn:field];
            return YES;
        }
        UIButton *send = [self findSendControl];
        if (send) {
            [send sendActionsForControlEvents:UIControlEventTouchUpInside];
            return YES;
        }
        [field sendActionsForControlEvents:UIControlEventEditingDidEndOnExit];
        return YES;
    }

    UITextView *textView = (UITextView *)target;
    textView.text = text;
    // textViewDidChange: 是可选协议方法,delegate 没实现时直接发消息会 unrecognized selector
    if ([textView.delegate respondsToSelector:@selector(textViewDidChange:)]) {
        [textView.delegate textViewDidChange:textView];
    }
    UIButton *send = [self findSendControl];
    if (send) {
        [send sendActionsForControlEvents:UIControlEventTouchUpInside];
        return YES;
    }
    for (UIView *view in [self viewsMatching:@[@"发送"] limit:4]) {
        if ([self tap:view]) return YES;
    }
    return NO;
}

+ (UIButton *)findSendControl {
    UIWindow *win = [self keyWindow];
    if (!win) return nil;
    __block UIButton *hit = nil;
    [self walkFrom:win block:^(UIView *view, NSInteger depth, BOOL *stop) {
        if (![view isKindOfClass:[UIButton class]]) return;
        UIButton *btn = (UIButton *)view;
        NSString *title = [btn titleForState:UIControlStateNormal] ?: btn.currentTitle;
        NSString *label = btn.accessibilityLabel;
        if ([self matches:title keywords:@[@"发送", @"Send"]] || [self matches:label keywords:@[@"发送", @"Send"]]) {
            if (btn.isUserInteractionEnabled && !btn.hidden) {
                hit = btn;
                *stop = YES;
            }
        }
    }];
    return hit;
}

#pragma mark - 切台

+ (BOOL)switchToNextRoom {
    UIWindow *win = [self keyWindow];
    if (!win) return NO;
    __block UIScrollView *best = nil;
    __block CGFloat bestArea = 0;
    [self walkFrom:win block:^(UIView *view, NSInteger depth, BOOL *stop) {
        if (![view isKindOfClass:[UIScrollView class]]) return;
        UIScrollView *sv = (UIScrollView *)view;
        CGSize size = sv.bounds.size;
        if (size.width < 200 || size.height < 200) return;
        if (sv.contentSize.height <= size.height * 1.2) return;
        CGFloat area = size.width * size.height;
        if (area > bestArea) {
            bestArea = area;
            best = sv;
        }
    }];
    if (!best) {
        FuLog(@"切台失败:未找到可翻页的信息流容器");
        return NO;
    }
    CGPoint offset = best.contentOffset;
    CGFloat page = best.bounds.size.height;
    if (page < 100) page = 600;
    CGFloat maxY = MAX(0, best.contentSize.height - best.bounds.size.height);
    CGFloat nextY = MIN(offset.y + page, maxY);
    if (nextY <= offset.y + 1) {
        nextY = offset.y + page;
    }
    [best setContentOffset:CGPointMake(offset.x, nextY) animated:YES];
    FuLog(@"切台:信息流偏移 %.0f → %.0f", offset.y, nextY);
    return YES;
}

@end
