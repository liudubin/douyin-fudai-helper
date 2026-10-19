//
//  FudaiScan.m
//

#import "FudaiScan.h"
#import "FudaiConfig.h"

static const NSInteger kMaxWalkNodes = 8000;
static const NSInteger kMaxWalkDepth = 60;

@interface FudaiScan (Private)
+ (void)walkFrom:(UIView *)root block:(void (^)(UIView *view, NSInteger depth, BOOL *stop))block;
+ (BOOL)matches:(NSString *)text keywords:(NSArray<NSString *> *)keywords;
+ (NSArray<UIView *> *)editableViews;
+ (UIButton *)findSendControl;
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

+ (BOOL)tap:(UIView *)view {
    if (!view) return NO;
    UIView *cursor = view;
    for (NSInteger i = 0; i < 6 && cursor; i++) {
        if ([cursor isKindOfClass:[UIControl class]] && cursor.isUserInteractionEnabled) {
            UIControl *control = (UIControl *)cursor;
            [control sendActionsForControlEvents:UIControlEventTouchUpInside];
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
    return NO;
}

+ (BOOL)tapFirstMatching:(NSArray<NSString *> *)keywords {
    NSArray<UIView *> *candidates = [self viewsMatching:keywords limit:6];
    for (UIView *view in candidates) {
        if ([self tap:view]) return YES;
    }
    return NO;
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
    [textView.delegate textViewDidChange:textView];
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
