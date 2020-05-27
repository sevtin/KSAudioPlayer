//
//  NAudioFileStream.m
//  NAudioFileStream
//
//  Created by 泽娄 on 2019/9/21.
//  Copyright © 2019 泽娄. All rights reserved.
//

#import "NAudioFileStream.h"
#import "NParseAudioData.h"

#define  BitRateEstimationMaxPackets 5000
#define  BitRateEstimationMinPackets 10

@interface NAudioFileStream ()
{
@private
    BOOL _discontinuous;
    
    SInt64 _dataOffset;
    NSTimeInterval _packetDuration; // 当前已读取了多少个packet
    UInt64 _audioDataByteCount;
    NSInteger _fileSize;

    UInt64 _processedPacketsCount;
    UInt64 _processedPacketsSizeTotal;
    
    UInt64 _seekByteOffset;
}

@property (nonatomic, copy) NSString *path;
@property (nonatomic, assign) BOOL available;
@property (nonatomic, assign) BOOL readyToProducePackets;

@property (nonatomic, assign, readwrite) AudioStreamBasicDescription audioStreamBasicDescription;

@property (nonatomic, assign, readwrite) AudioFileStreamID audioFileStreamID;

@property (nonatomic, assign, readwrite) NSTimeInterval duration; /// 时长

@property (nonatomic, assign, readwrite) UInt32 bitRate; /// 速率

@property (nonatomic, assign) UInt32 maxPacketSize;

@end

@implementation NAudioFileStream

- (instancetype)initWithFilePath:(NSString *)path fileSize:(NSInteger )fileSize
{
    self = [super init];
    if (self) {
        _path = path;
        NSLog(@"文件总长度, NAudioFileStream, _fileSize: %ld", (long)_fileSize);
        _fileSize = fileSize;
        [self createAudioFileStream];
    }return self;
}

- (void)createAudioFileStream
{
    /*
     AudioFileStreamOpen的参数说明如下：
     1. inClientData：用户指定的数据，用于传递给回调函数，这里我们指定(__bridge NAudioFileStream*)self
     2. inPropertyListenerProc：当解析到一个音频信息时，将回调该方法
     3. inPacketsProc：当解析到一个音频帧时，将回调该方法
     4. inFileTypeHint：指明音频数据的格式，如果你不知道音频数据的格式，可以传0
     5. outAudioFileStream：AudioFileStreamID实例，需保存供后续使用
     */
    
    OSStatus status = AudioFileStreamOpen((__bridge void *)self, NAudioFileStreamPropertyListener, NAudioFileStreamPacketCallBack, 0, &_audioFileStreamID);
    
    if (status != noErr) {
        _audioFileStreamID = NULL;
        NSLog(@"_audioFileStreamID is null");
    }
    
    NSError *error;
    
    [self _errorForOSStatus:status error:&error];
}

- (void)parseData:(NSData *)data
{
    /// 解析数据
    /// NSLog(@"每次读取data.length: %u", (unsigned int)data.length);
    
    if (!_audioFileStreamID) {
        NSLog(@"audioFileStreamID is null");
        return;
    }
    
    OSStatus status = AudioFileStreamParseBytes(_audioFileStreamID, (UInt32)data.length, data.bytes, 0);
    
    if (status != noErr) {
        NSLog(@"AudioFileStreamParseBytes 失败");
    }
    
    /// NSLog(@"AudioFileStreamParseBytes 成功");

//    do {
//        self.audioFileData = [self.audioFileHandle readDataOfLength:kAudioFileBufferSize];
        
        /*
            参数的说明如下：
            1. inAudioFileStream：AudioFileStreamID实例，由AudioFileStreamOpen打开
            2. inDataByteSize：此次解析的数据字节大小
            3. inData：此次解析的数据大小
            4. inFlags：数据解析标志，其中只有一个值kAudioFileStreamParseFlag_Discontinuity = 1，表示解析的数据是否是不连续的，目前我们可以传0。
        */
//
//        OSStatus error = AudioFileStreamParseBytes(_audioFileStreamID, (UInt32)self.audioFileData.length, self.audioFileData.bytes, 0);
//
//        if (error != noErr) {
//            NSLog(@"AudioFileStreamParseBytes 失败");
//        }
        
//    } while (self.audioFileData != nil && self.audioFileData.length > 0);
    
    
//    [self.audioFileHandle closeFile];
//    [self close]; /// 关闭文件
}

/// 拖动进度条，需要到几分几秒，而我们实际上操作的是文件，即寻址到第几个字节开始播放音频数据
- (unsigned long long)seekToTime:(double)newTime
{
    if (_bitRate == 0.0 || _fileSize <= 0){
        NSLog(@"_bitRate, _fileLength is 0");
        return 0.0;
    }
    
    /// 近似seekByteOffset = 数据偏移 + seekToTime对应的近似字节数
    _seekByteOffset = _dataOffset + (newTime / _duration) * (_fileSize - _dataOffset);
    
//    if (_seekByteOffset > _fileSize - 2 * packetBufferSize){
//        _seekByteOffset = _fileSize - 2 * packetBufferSize;
//    }
        
    if (_packetDuration > 0) {
        /*
         1. 首先需要计算每个packet对应的时长_packetDuration
         2. 再然后计算_packetDuration位置seekToPacket
         */
        SInt64 seekToPacket = floor(newTime / _packetDuration);
        
        UInt32 ioFlags = 0;
        SInt64 outDataByteOffset;
        OSStatus status = AudioFileStreamSeek(_audioFileStreamID, seekToPacket, &outDataByteOffset, &ioFlags);
        NSLog(@"seek status : %d, _seekByteOffset: %llu", status, _seekByteOffset);
        if ((status == noErr) && !(ioFlags & kAudioFileStreamSeekFlag_OffsetIsEstimated)){
            _seekByteOffset = outDataByteOffset + _dataOffset;
        }
    }
    
    NSLog(@"_seekByteOffset: %llu, _fileSize: %ld", _seekByteOffset, (long)_fileSize);
    
    /// 继续播放的操作, audioQueue处理
    return _seekByteOffset;
}

#pragma mark - open & close
- (void)close
{
    if (!_audioFileStreamID) {
        NSLog(@"audioFileStreamID is null");
        return;
    }
     
    OSStatus status = AudioFileStreamClose(_audioFileStreamID);
    
    if (status != noErr) {
        NSLog(@"AudioFileStreamClose 失败");
        return;
    }
    
    _audioFileStreamID = NULL;
}

/// 音频文件读取速率
- (UInt32)calculateBitRate
{
    if (_packetDuration && _processedPacketsCount > BitRateEstimationMinPackets && _processedPacketsCount <= BitRateEstimationMaxPackets){
        double averagePacketByteSize = _processedPacketsSizeTotal / _processedPacketsCount;
        return _bitRate = 8.0 * averagePacketByteSize / _packetDuration;
    }
    return 0.0;
}

/// 音频文件总时长
- (void)calculateDuration
{
    if (_fileSize > 0 && _bitRate > 0){
        _duration = ((_fileSize - _dataOffset) * 8.0) / _bitRate;
    }
}

/// 首先需要计算每个packet对应的时长
- (void)calculatePacketDuration
{
    if (_audioStreamBasicDescription.mSampleRate > 0) {
        _packetDuration = _audioStreamBasicDescription.mFramesPerPacket / _audioStreamBasicDescription.mSampleRate;
    }
    
    NSLog(@"当前已读取了多少个packet, %.2f", _packetDuration);
}

- (UInt32)bitRate
{
    return [self calculateBitRate];
}

 - (NSTimeInterval)duration
{
    return ((_fileSize - _dataOffset) * 8.0) / _bitRate;
}

#pragma mark - private method
- (void)_errorForOSStatus:(OSStatus)status error:(NSError *__autoreleasing *)outError
{
    if (status != noErr && outError != NULL) {
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    }
}

- (void)handleAudioFileStreamProperty:(AudioFileStreamPropertyID)propertyID
{
    if (propertyID == kAudioFileStreamProperty_ReadyToProducePackets) {
        /*
         该属性告诉我们，已经解析到完整的音频帧数据，准备产生音频帧，之后会调用到另外一个回调函数。之后便是音频数据帧的解析。
         */
        _readyToProducePackets = YES;
        _discontinuous = YES;
        
        UInt32 sizeOfUInt32 = sizeof(_maxPacketSize);
        OSStatus status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_PacketSizeUpperBound, &sizeOfUInt32, &_maxPacketSize);
        
        if (status != noErr || _maxPacketSize == 0) {
            status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_ReadyToProducePackets, &sizeOfUInt32, &_maxPacketSize);
        }
        
        NSLog(@">>>>>>> kAudioFileStreamProperty_ReadyToProducePackets <<<<<<<");
        
        NSLog(@">>>>>>> 准备音频数据帧的解析 <<<<<<<");

        /// 准备解析音频数据帧
        if (self.delegate && [self.delegate respondsToSelector:@selector(audioStream_readyToProducePacketsWithAudioFileStream:)]) {
            [self.delegate audioStream_readyToProducePacketsWithAudioFileStream:self];
        }
        
    }else if (propertyID == kAudioFileStreamProperty_DataOffset){
        /*
    表示音频数据在整个音频文件的offset，因为大多数音频文件都会有一个文件头。个值在seek时会发挥比较大的作用，音频的seek并不是直接seek文件位置而seek时间（比如seek到2分10秒的位置），seek时会根据时间计算出音频数据的字节offset然后需要再加上音频数据的offset才能得到在文件中的真正offset。
         */
        
        SInt64 offset;
        UInt32 offsetSize = sizeof(offset);
        OSStatus status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_DataOffset, &offsetSize, &offset);
        if (status){
//            [self failWithErrorCode:AS_FILE_STREAM_GET_PROPERTY_FAILED];
            return;
        }
        
        NSLog(@">>>>>>> kAudioFileStreamProperty_DataOffset <<<<<<<");

        _dataOffset = offset; 
        /// _audioDataByteCount = _fileLength - _dataOffset;
        [self calculateDuration];
    }else if (propertyID == kAudioFileStreamProperty_AudioDataByteCount){
        UInt32 audioDataByteCount;
        UInt32 byteCountSize = sizeof(audioDataByteCount);
        OSStatus status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_AudioDataByteCount, &byteCountSize, &audioDataByteCount);
        
        if (status == noErr) {
//            NSLog(@"audioDataByteCount : %u, byteCountSize: %u",audioDataByteCount,byteCountSize);
        }
        
        _audioDataByteCount = audioDataByteCount;

        NSLog(@">>>>>>> kAudioFileStreamProperty_AudioDataByteCount <<<<<<<");
    }else if (propertyID == kAudioFileStreamProperty_DataFormat){
        /*
         表示音频文件结构信息，是一个AudioStreamBasicDescription
         */
        if (_audioStreamBasicDescription.mSampleRate == 0){
            UInt32 asbdSize = sizeof(_audioStreamBasicDescription);
            
            // get the stream format.
            OSStatus status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_DataFormat, &asbdSize, &_audioStreamBasicDescription);
            
            if (status == noErr) {
                // NSLog(@"audioDataByteCount : %u, byteCountSize: %u",audioDataByteCount,byteCountSize);
            }
            
            /// 首先需要计算每个packet对应的时长
            [self calculatePacketDuration];

            //        if (status){
            ////                [self failWithErrorCode:AS_FILE_STREAM_GET_PROPERTY_FAILED];
            //            return;
            //        }
        }
    
        NSLog(@">>>>>>> kAudioFileStreamProperty_DataFormat <<<<<<<");
    } else if (propertyID == kAudioFileStreamProperty_FormatList){
        Boolean outWriteable;
        UInt32 formatListSize;
        OSStatus status = AudioFileStreamGetPropertyInfo(_audioFileStreamID, kAudioFileStreamProperty_FormatList, &formatListSize, &outWriteable);
        if (status)
        {
//            [self failWithErrorCode:AS_FILE_STREAM_GET_PROPERTY_FAILED];
            return;
        }
        
        AudioFormatListItem *formatList = malloc(formatListSize);
        status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_FormatList, &formatListSize, formatList);
        if (status)
        {
            free(formatList);
//            [self failWithErrorCode:AS_FILE_STREAM_GET_PROPERTY_FAILED];
            return;
        }

        for (int i = 0; i * sizeof(AudioFormatListItem) < formatListSize; i += sizeof(AudioFormatListItem))
        {
            AudioStreamBasicDescription pasbd = formatList[i].mASBD;
            if (pasbd.mFormatID == kAudioFormatMPEG4AAC_HE ||
                pasbd.mFormatID == kAudioFormatMPEG4AAC_HE_V2)
            {
                //
                // We've found HE-AAC, remember this to tell the audio queue
                // when we construct it.
                //
#if !TARGET_IPHONE_SIMULATOR
                _audioStreamBasicDescription = pasbd;
#endif
                break;
            }
        }
        free(formatList);
        
        NSLog(@">>>>>>> kAudioFileStreamProperty_FormatList <<<<<<<");
    }
    
}

- (void)handleAudioFileStreamInputData:(const void *)inputData
                         inNumberBytes:(UInt32)inNumberBytes
                       inNumberPackets:(UInt32)inNumberPackets
                     packetDescription:(AudioStreamPacketDescription *)packetDescriptions
{
    if (_discontinuous) {
        _discontinuous = NO;
    }
    
    if (inNumberBytes == 0 || inNumberPackets == 0) {
        NSLog(@"inNumberBytes: %d, inNumberPackets: %d", inNumberBytes, inNumberPackets);
        return;
    }
    
    if (packetDescriptions == NULL) {
        NSLog(@"packetDescriptions is null");
        return;
    }
    
    for (int i = 0; i < inNumberPackets; ++i){
        if (_processedPacketsCount < BitRateEstimationMaxPackets){
            _processedPacketsSizeTotal += packetDescriptions[i].mDataByteSize;
            _processedPacketsCount += 1;
            [self calculateBitRate];
            [self calculateDuration];
        }
    }
    
    NSData *data = [NSData dataWithBytes:inputData length:inNumberBytes];
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(audioStream_packetsWithAudioFileStream:data:inputData:inNumberBytes:inNumberPackets:inPacketDescrrptions:)]) {
        [self.delegate audioStream_packetsWithAudioFileStream:nil
                                                         data:data
                                                    inputData:inputData
                                                inNumberBytes:inNumberBytes
                                              inNumberPackets:inNumberPackets
                                         inPacketDescrrptions:packetDescriptions];
    }
}

#pragma mark - static callbacks
static void NAudioFileStreamPropertyListener(void *inClientData,AudioFileStreamID inAudioFileStream, AudioFileStreamPropertyID inPropertyID, UInt32 *inFlags)
{
    NAudioFileStream *audioFileStream = (__bridge NAudioFileStream *)inClientData;
    [audioFileStream handleAudioFileStreamProperty:inPropertyID];
}

static void NAudioFileStreamPacketCallBack(void *inClientData, UInt32 inNumberBytes, UInt32 inNumberPackets, const void *inInputData, AudioStreamPacketDescription *inPacketDescrrptions)
{
    NAudioFileStream *audioFileStream = (__bridge NAudioFileStream *)inClientData;
    [audioFileStream handleAudioFileStreamInputData:inInputData inNumberBytes:inNumberBytes inNumberPackets:inNumberPackets packetDescription:inPacketDescrrptions];
}

/*
 
 //当解析到一个音频帧时，将回调该方法
 void AudioFileStreamPacketsProc(void *inClientData,
                                 UInt32 inNumberBytes,
                                 UInt32 inNumberPackets,
                                 const void *inInputData,
                                 AudioStreamPacketDescription *inPacketDescriptions){
     
     NAudioQueue *_audioQueue = (__bridge NAudioQueue *)inClientData;
     
     if (inPacketDescriptions) {
         for (int i = 0; i < inNumberPackets; i++) {
             SInt64 mStartOffset = inPacketDescriptions[i].mStartOffset;
             UInt32 mDataByteSize = inPacketDescriptions[i].mDataByteSize;
             
             //如果当前要填充的数据大于缓冲区剩余大小，将当前buffer送入播放队列，指示将当前帧放入到下一个buffer
             if (mDataByteSize > kAudioFileBufferSize - _audioQueue.audioDataBytesFilled) {
                 NSLog(@"当前buffer_%ld已经满了，送给audioqueue去播吧",(long)_audioQueue->_audioBufferIndex);
                 _audioQueue->inuse[_audioQueue.audioBufferIndex] = YES;
                 
                 OSStatus err = AudioQueueEnqueueBuffer(_audioQueue->audioQueue, _audioQueue->audioQueueBuffer[_audioQueue.audioBufferIndex], (UInt32)_audioQueue.audioPacketsFilled, _audioQueue->audioStreamPacketDesc);
                 if (err == noErr) {
                     
                     if (!_audioQueue.isPlaying) {
                         err = AudioQueueStart(_audioQueue->audioQueue, NULL);
                         if (err != noErr) {
                             NSLog(@"play failed");
                             continue;
                         }
                         _audioQueue.playing = YES;
                     }
                     
                     _audioQueue.audioBufferIndex = (++_audioQueue.audioBufferIndex) % kNumberOfBuffers;
                     _audioQueue.audioPacketsFilled = 0;
                     _audioQueue.audioDataBytesFilled = 0;
                     
                     //                    // wait until next buffer is not in use
                     //                    pthread_mutex_lock(&audioPlayer->mutex);
                     //                    while (audioPlayer->inuse[audioPlayer.audioBufferIndex]) {
                     //                        printf("... WAITING ...\n");
                     //                        pthread_cond_wait(&audioPlayer->cond, &audioPlayer->mutex);
                     //                    }
                     //                    pthread_mutex_unlock(&audioPlayer->mutex);
                     //                    printf("WaitForFreeBuffer->unlock\n");
                     
                     while (_audioQueue->inuse[_audioQueue->_audioBufferIndex]);
                 }
             }
             
             NSLog(@"给当前buffer_%ld填装数据中",(long)_audioQueue->_audioBufferIndex);
             AudioQueueBufferRef currentFillBuffer = _audioQueue->audioQueueBuffer[_audioQueue.audioBufferIndex];
             memcpy(currentFillBuffer->mAudioData + _audioQueue.audioDataBytesFilled, inInputData + mStartOffset, mDataByteSize);
             currentFillBuffer->mAudioDataByteSize = (UInt32)(_audioQueue.audioDataBytesFilled + mDataByteSize);
             
             _audioQueue->audioStreamPacketDesc[_audioQueue.audioPacketsFilled] = inPacketDescriptions[i];
             _audioQueue->audioStreamPacketDesc[_audioQueue.audioPacketsFilled].mStartOffset = _audioQueue.audioDataBytesFilled;
             _audioQueue.audioDataBytesFilled += mDataByteSize;
             _audioQueue.audioPacketsFilled += 1;
         }
     }else{
         
     }
 }
 
 */

@end
