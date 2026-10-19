//
//  FudaiPanel.h
//  悬浮球 + 底部 sheet 面板(主页 / 参数 / 日志)
//
//  截图基准:深色 sheet 全宽、三段 tab、统计三列、总开关卡、巡逻模式分段、
//  六个功能开关、底行「复制诊断 / 隐藏面板」、脚注引擎行。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "FudaiConfig.h"

#ifndef FudaiPanel
#define FudaiPanel Fu2
#endif

@interface FudaiPanel : NSObject

+ (instancetype)shared;

/// App 启动完成后调用:挂引擎回调 + 首次挂载悬浮球
- (void)setup;

/// 定时兜底:window 变化后重新挂载悬浮球(隐藏抽屉 / 旋转 / 场景切换)
- (void)attachIfNeeded;

/// 打开面板(底部 sheet 全宽)
- (void)present;

/// 收起面板
- (void)dismiss;

/// 抖音设置页入口按钮回调(Tweak.x 经 action 调)
- (void)spOpenFromSettings;

/// 复制诊断到剪贴板(面板按钮)
- (void)copyDiagnostic;

@end
