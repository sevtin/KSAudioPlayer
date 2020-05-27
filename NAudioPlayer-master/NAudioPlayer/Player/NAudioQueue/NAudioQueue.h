//
//  NAudioQueue.h
//  NAudioPlayer
//
//  Created by 泽娄 on 2019/9/22.
//  Copyright © 2019 泽娄. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

NS_ASSUME_NONNULL_BEGIN

@interface NAudioQueue : NSObject

/// 该属性指明了音频数据的格式信息，返回的数据是一个AudioStreamBasicDescription结构
@property (nonatomic, assign, readonly) AudioStreamBasicDescription audioStreamBasicDescription;

@property (nonatomic, assign, readonly) AudioQueueRef audioQueue; /// audio queue实例

@property (nonatomic, assign, readonly) AudioFileStreamID audioFileStreamID;

@property (nonatomic,assign, readonly) NSTimeInterval playedTime;

/// 音频文件描述信息
- (instancetype)initWithAudioDesc:(AudioStreamBasicDescription)audioDesc
                audioFileStreamID:(AudioFileStreamID)audioFileStreamID;

/// 开始
- (void)start;

///  暂停
- (void)pause;

///  停止
- (void)stop;

/// 重置
- (void)reset;

/**
 *  Play audio data, data length must be less than bufferSize.
 *  Will block current thread until the buffer is consumed.
 *
 *  @param data               data
 *  @param inNumberPackets        packet count
 *  @param packetDescriptions packet desccriptions
 *
 */
- (void)playData:(NSData *)data
       inputData:(nonnull const void *)inputData
 inNumberPackets:(UInt32)inNumberPackets
packetDescriptions:(AudioStreamPacketDescription *)packetDescriptions
           isEof:(BOOL)isEof;

@end

NS_ASSUME_NONNULL_END
