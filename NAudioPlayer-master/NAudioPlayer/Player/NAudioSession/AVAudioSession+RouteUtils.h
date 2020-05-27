//
//  AVAudioSession+RouteUtils.h
//  NAudioSession
//
//  Created by 泽娄 on 2019/9/18.
//  Copyright © 2019 泽娄. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface AVAudioSession (RouteUtils)

/// 使用蓝牙
- (BOOL)usingBlueTooth;

/// 使用有线麦克风
- (BOOL)usingWiredMicrophone;

/// 显示耳机警报
- (BOOL)shouldShowEarphoneAlert;

@end
