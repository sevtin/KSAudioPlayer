//
//  NParseAudioData.h
//  NAudioFileStream
//
//  Created by 泽娄 on 2019/9/21.
//  Copyright © 2019 泽娄. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudioTypes.h>

NS_ASSUME_NONNULL_BEGIN

@interface NParseAudioData : NSObject

@property (nonatomic, readonly) NSData *data;
@property (nonatomic, readonly) AudioStreamPacketDescription packetDescription;

+ (instancetype)parsedAudioDataWithBytes:(const void *)bytes packetDescription:(AudioStreamPacketDescription)packetDescription;

@end

NS_ASSUME_NONNULL_END
