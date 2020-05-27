//
//  NParseAudioData.m
//  NAudioFileStream
//
//  Created by 泽娄 on 2019/9/21.
//  Copyright © 2019 泽娄. All rights reserved.
//

#import "NParseAudioData.h"

@implementation NParseAudioData

@synthesize  data = _data;
@synthesize  packetDescription = _packetDescription;

+ (instancetype)parsedAudioDataWithBytes:(const void *)bytes packetDescription:(AudioStreamPacketDescription)packetDescription
{
    return [[self alloc]initWithBytes:bytes packetDescription:packetDescription];
}

- (instancetype)initWithBytes:(const void *)bytes packetDescription:(AudioStreamPacketDescription)packDescription
{
    if (bytes == NULL || packDescription.mDataByteSize == 0) {
        return nil;
    }
    if (self = [super init]) {
        _data = [NSData dataWithBytes:bytes length:packDescription.mDataByteSize];
        _packetDescription = packDescription;
    }
    return self;
}

@end
