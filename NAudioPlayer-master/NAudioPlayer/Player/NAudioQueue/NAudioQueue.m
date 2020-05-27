//
//  NAudioQueue.m
//  NAudioPlayer
//
//  Created by 泽娄 on 2019/9/22.
//  Copyright © 2019 泽娄. All rights reserved.
//

#import "NAudioQueue.h"
#import "NAudioSession.h"
#include <pthread.h>

#define kNumberOfBuffers 3              // AudioQueueBuffer数量，一般指明为3
#define kAQBufSize 10 * 1024        // 每个AudioQueueBuffer须要开辟的缓冲区的大小 10 * 1024

#define kAQMaxPacketDescs 512

#define kAQDefaultBufSize 2048    // 每个buffer装的bytes

@interface NAudioQueue ()
{
    AudioQueueBufferRef audioQueueBuffer[kNumberOfBuffers];
    NSLock *_lock; /// 锁
    BOOL inUsed[kNumberOfBuffers];//标记当前buffer是否正在被使用
    UInt32 currBufferIndex; //当前使用的buffer的索引
    UInt32 currBufferFillOffset;//当前buffer已填充的数据量
    UInt32 currBufferPacketCount;//当前是第几个packet,  当前填充了多少帧
    
    double sampleRate;
                                
    double packetDuration;
    UInt32 packetBufferSize;
    UInt32 bytesFilled;
    bool inuse[kNumberOfBuffers];
    unsigned int fillBufferIndex;
    UInt32 packetsFilled;
    UInt64 processedPacketsCount;
    AudioStreamPacketDescription packetDescs[kAQMaxPacketDescs];
    
    pthread_mutex_t queueBuffersMutex;
    pthread_cond_t queueBufferReadyCondition;
    bool _started;
}

/// 该属性指明了音频数据的格式信息，返回的数据是一个AudioStreamBasicDescription结构
@property (nonatomic, assign, readwrite) AudioStreamBasicDescription audioStreamBasicDescription;

@property (nonatomic, assign, readwrite) AudioFileStreamID audioFileStreamID;

@property (nonatomic, assign, readwrite) AudioQueueRef audioQueue; /// audio queue实例

@property (nonatomic, assign, readwrite) NSTimeInterval playedTime;

@end

@implementation NAudioQueue
/// 音频文件描述信息
- (instancetype)initWithAudioDesc:(AudioStreamBasicDescription)audioDesc
                audioFileStreamID:(AudioFileStreamID)audioFileStreamID
{
    self = [super init];
    if (self) {
        _started = NO;
        currBufferIndex = 0;
        currBufferFillOffset = 0;
        currBufferPacketCount = 0;
        _audioStreamBasicDescription = audioDesc;
        _audioFileStreamID = audioFileStreamID;
        [self createAudioSession];
        [self createPthread];
        [self createAudioQueue];
    }return self;
}

- (void)createAudioSession
{
    [[NAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback]; /// 支持视频、音频播放
    [[NAudioSession sharedInstance] setPreferredSampleRate:44100];
    [[NAudioSession sharedInstance] setActive:YES];
    [[NAudioSession sharedInstance] addRouteChangeListener];
}

- (void)createPthread
{
    pthread_mutex_init(&queueBuffersMutex, NULL);
    pthread_cond_init(&queueBufferReadyCondition, NULL);
}

/*
 参数及返回说明如下：
 1. inFormat：该参数指明了即将播放的音频的数据格式
 2. inCallbackProc：该回调用于当AudioQueue已使用完一个缓冲区时通知用户，用户可以继续填充音频数据
 3. inUserData：由用户传入的数据指针，用于传递给回调函数
 4. inCallbackRunLoop：指明回调事件发生在哪个RunLoop之中，如果传递NULL，表示在AudioQueue所在的线程上执行该回调事件，一般情况下，传递NULL即可。
 5. inCallbackRunLoopMode：指明回调事件发生的RunLoop的模式，传递NULL相当于kCFRunLoopCommonModes，通常情况下传递NULL即可
 6. outAQ：该AudioQueue的引用实例，
 */
- (void)createAudioQueue
{
    sampleRate = self.audioStreamBasicDescription.mSampleRate;
    packetDuration = self.audioStreamBasicDescription.mFramesPerPacket / sampleRate;
    
    NSLog(@"createAudioQueue, sampleRate:%.2f, packetDuration:%.2f", sampleRate, packetDuration);
    
    OSStatus status;
    status = AudioQueueNewOutput(&_audioStreamBasicDescription, NAudioQueueOutputCallback, (__bridge void * _Nullable)(self), NULL, NULL, 0, &_audioQueue);
    
    if (status != noErr) {
        NSLog(@"AudioQueueNewOutput 失败");
        return;
    }
    
    NSLog(@"AudioQueueNewOutput 成功");

    // 监听 isRunning
    status = AudioQueueAddPropertyListener(_audioQueue, kAudioQueueProperty_IsRunning, ASAudioQueueIsRunningCallback, (__bridge void * _Nullable)(self));
    
    if (status) {
        NSLog(@"AudioQueueNewOutput error");
        return;
    }
    

    UInt32 sizeOfUInt32 = sizeof(UInt32);
    status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_PacketSizeUpperBound, &sizeOfUInt32, &packetBufferSize);
    if (status || packetBufferSize == 0)
    {
        status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_MaximumPacketSize, &sizeOfUInt32, &packetBufferSize);
        if (status || packetBufferSize == 0)
        {
            packetBufferSize = kAQDefaultBufSize;
        }
    }

    NSLog(@"packetBufferSize: %d", packetBufferSize);
    
    [self createBuffer];
    
    UInt32 cookieSize;
    Boolean writable;
    OSStatus ignorableError;
    ignorableError = AudioFileStreamGetPropertyInfo(_audioFileStreamID, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable);
    if (ignorableError)
    {
        return;
    }

    void* cookieData = calloc(1, cookieSize);
    ignorableError = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_MagicCookieData, &cookieSize, cookieData);
    if (ignorableError)
    {
        return;
    }

    ignorableError = AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_MagicCookie, cookieData, cookieSize);
    free(cookieData);
    if (ignorableError)
    {
        return;
    }
    
    // 设置音量
    AudioQueueSetParameter(_audioQueue, kAudioQueueParam_Volume, 1.0);
}

/*
 该方法的作用是为存放音频数据的缓冲区开辟空间

 参数及返回说明如下：
 1. inAQ：AudioQueue的引用实例
 2. inBufferByteSize：需要开辟的缓冲区的大小
 3. outBuffer：开辟的缓冲区的引用实例
 */
- (void)createBuffer
{
    OSStatus status;
    for (int i = 0; i < kNumberOfBuffers; i++) {
        status = AudioQueueAllocateBuffer(_audioQueue, kAQBufSize, &audioQueueBuffer[i]);
        inUsed[i] = NO; /// 默认都是未使用
        if (status != noErr) {
            NSLog(@"AudioQueueAllocateBuffer 失败!!!");
            continue;
        }
    }
    
    NSLog(@"AudioQueueAllocateBuffer 成功!!!");
}

/// 开始
- (void)start
{
    if (!_audioQueue) {
        NSLog(@"audioQueue is null!!!");
        return;
    }
  
    OSStatus status;
    /// 队列处理开始，此后系统开始自动调用回调(Callback)函数
    status = AudioQueueStart(_audioQueue, nil);
    
    if (status != noErr) {
        NSLog(@"AudioQueueStart 失败!!!");
    }
    
    NSLog(@"AudioQueueStart 成功!!!");
    
    /// 标记start始成功
    _started = YES;
}

/// 暂停
- (void)pause
{
    _started = NO;

    if (!_audioQueue) {
        NSLog(@"audioQueue is null!!!");
        return;
    }
    
    OSStatus status= AudioQueuePause(_audioQueue);
    if (status!= noErr){
//        [self.audioProperty error:LLYAudioError_AQ_PauseFail];
        return;
    }
    NSLog(@"pause, status: %d", status);
}

/// 停止
- (void)stop
{
    _started = NO;

    if (!_audioQueue) {
        NSLog(@"audioQueue is null!!!");
        return;
    }

     OSStatus status= AudioQueueStop(_audioQueue, YES);
     if (status!= noErr){
        //   [self.audioProperty error:LLYAudioError_AQ_StopFail];
        return;
     }

    NSLog(@"stop, status: %d, _started: %d", status, _started);
}

/// 重置
- (void)reset
{
    _started = NO;

    if (!_audioQueue) {
        NSLog(@"audioQueue is null!!!");
        return;
    }

    OSStatus status = AudioQueueReset(_audioQueue);
    if (status!= noErr){
       //   [self.audioProperty error:LLYAudioError_AQ_StopFail];
       return;
    }
    
    NSLog(@"reset, status: %d", status);
}

/// 销毁
- (void)dispose
{
    if (!_audioQueue) {
       NSLog(@"audioQueue is null!!!");
       return;
    }

   OSStatus status = AudioQueueDispose(_audioQueue, YES);
   if (status!= noErr){
      //   [self.audioProperty error:LLYAudioError_AQ_StopFail];
      return;
   }
       
   NSLog(@"dispose, status: %d", status);
}

/// 回收buffer
- (void)freeBuffer
{
    for (NSInteger i = 0; i < kNumberOfBuffers; i++) {
        OSStatus status = AudioQueueFreeBuffer(_audioQueue, audioQueueBuffer[i]);
        if (status!= noErr){
            //   [self.audioProperty error:LLYAudioError_AQ_StopFail];
            return;
        }
        NSLog(@"freeBuffer, status: %d", status);
    }
}


- (void)playData:(NSData *)data
       inputData:(nonnull const void *)inputData
 inNumberPackets:(UInt32)inNumberPackets
packetDescriptions:(AudioStreamPacketDescription *)packetDescriptions
           isEof:(BOOL)isEof
{
    [_lock lock];
    
    if (inputData == NULL) {
        NSLog(@"inputData is null");
        [_lock unlock];
        return;
    }
    
    if (packetDescriptions == NULL) {
        NSLog(@"packetDescriptions is null");
        [_lock unlock];
        return;
    }
        
    for (int i = 0; i < inNumberPackets; ++i) {
       /// 获取 AudioStreamPacketDescription对象
        AudioStreamPacketDescription packetDesc = packetDescriptions[i];
        SInt64 packetOffset = packetDesc.mStartOffset;
        UInt32 packetSize = packetDesc.mDataByteSize;
        
        if ((packetSize + bytesFilled) >= packetBufferSize) {
            /*
             该方法用于将已经填充数据的AudioQueueBuffer入队到AudioQueue
            */
            /// NSLog(@"当前buffer_%u已经满了，送给audioqueue去播吧",(unsigned int)fillBufferIndex);
            
            [self enqueueBuffer];
        }
        
        /// NSLog(@"给当前buffer_%u填装数据中",(unsigned int)fillBufferIndex);
        
        /// 给当前buffer填充数据
        @synchronized(self)
        {
            /// 应该去播放的
            if (packetSize + bytesFilled > packetBufferSize){
                return;
            }
            /// 给当前buffer填充数据
            AudioQueueBufferRef fillBuf = audioQueueBuffer[fillBufferIndex];
            memcpy((char*)fillBuf->mAudioData + bytesFilled, (const char*)inputData + packetOffset, packetSize);
            fillBuf->mAudioDataByteSize = bytesFilled + packetSize;

            // 填充packetDescs
            packetDescs[packetsFilled] = packetDescriptions[i];
            packetDescs[packetsFilled].mStartOffset = bytesFilled;
            
            bytesFilled += packetSize;
            packetsFilled += 1;
        }
    }
    
    [_lock unlock];
}

- (void)enqueueBuffer
{
    @synchronized(self){
        inuse[fillBufferIndex] = YES;
        OSStatus status;
        AudioQueueBufferRef fillBuf = audioQueueBuffer[fillBufferIndex];
        if (packetsFilled > 0){
            status = AudioQueueEnqueueBuffer(_audioQueue, fillBuf, packetsFilled, packetDescs);
        }else{
            status = AudioQueueEnqueueBuffer(_audioQueue, fillBuf, 0, NULL);
        }
        
        if (status != noErr) {
            NSLog(@"enqueueBuffer error, status: %d", status);
            return;
        }
        
        if (!_started) {
            NSLog(@"播放开始, status: %d, fillBufferIndex: %u", status, fillBufferIndex);
            [self start];
        }
        
        // 取出下一个buffer
        if (++fillBufferIndex >= kNumberOfBuffers) fillBufferIndex = 0;
        bytesFilled = 0;        // 重置 bytesFilled
        packetsFilled = 0;        // 重置 packetsFilled
    }

    pthread_mutex_lock(&queueBuffersMutex);
    while (inuse[fillBufferIndex]){
        pthread_cond_wait(&queueBufferReadyCondition, &queueBuffersMutex);
    }
    pthread_mutex_unlock(&queueBuffersMutex);
}

#pragma mark private method

- (void)p_audioQueueOutput:(AudioQueueRef)inAQ inBuffer:(AudioQueueBufferRef)inBuffer
{
        unsigned int bufIndex = -1;
        for (unsigned int i = 0; i < kNumberOfBuffers; ++i){
            if (inBuffer == audioQueueBuffer[i]){
                /// NSLog(@"当前buffer_%d的数据已经播放完了 还给程序继续装数据去吧！！！！！！", i);
                bufIndex = i;
                break;
            }
        }
        
        if (bufIndex == -1){
            // [self failWithErrorCode:AS_AUDIO_QUEUE_BUFFER_MISMATCH];
            pthread_mutex_lock(&queueBuffersMutex);
            pthread_cond_signal(&queueBufferReadyCondition);
            pthread_mutex_unlock(&queueBuffersMutex);
            return;
        }
        
        pthread_mutex_lock(&queueBuffersMutex);
        inuse[bufIndex] = false;
        pthread_cond_signal(&queueBufferReadyCondition);
        pthread_mutex_unlock(&queueBuffersMutex);
}

/*
    该回调用于当AudioQueue已使用完一个缓冲区时通知用户，用户能够继续填充音频数据
 */
static void NAudioQueueOutputCallback(void *inUserData, AudioQueueRef inAQ,
                                        AudioQueueBufferRef buffer){
    NAudioQueue *_audioQueue = (__bridge NAudioQueue *)inUserData;
    if (_audioQueue != nil) {
        [_audioQueue p_audioQueueOutput:inAQ inBuffer:buffer];
    }
}

static void ASAudioQueueIsRunningCallback(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    NAudioQueue *_audioQueue = (__bridge NAudioQueue *)inUserData;
    if (_audioQueue != nil) {
        [_audioQueue handlePropertyChangeForQueue:inAQ propertyID:inID];
    }
}

- (void)handlePropertyChangeForQueue:(AudioQueueRef)inAQ
    propertyID:(AudioQueuePropertyID)inID
{
    @autoreleasepool {
        @synchronized(self){
            if (inID == kAudioQueueProperty_IsRunning){
                UInt32 isRunning = 0;
                UInt32 size = sizeof(UInt32);
                AudioQueueGetProperty(_audioQueue, inID, &isRunning, &size);
                NSLog(@"监听audioQueue播放状态, _started: %d, isRunning: %d", _started, isRunning);
                /// 监听audioQueue播放状态
                if (!isRunning) {
                    _started = NO;
                }
            }
        }
    }
}

#pragma mark - property
- (NSTimeInterval)playedTime
{
    if (_audioStreamBasicDescription.mSampleRate == 0) {
        return 0;
    }
    
    AudioTimeStamp time;
    OSStatus status = AudioQueueGetCurrentTime(_audioQueue, NULL, &time, NULL);
    if (status == noErr) {
        _playedTime = time.mSampleTime / _audioStreamBasicDescription.mSampleRate;
    }
    
    return _playedTime;
}

- (void)dealloc
{
    [self dispose];
    _started = NO;
    currBufferIndex = 0;
    currBufferFillOffset = 0;
    currBufferPacketCount = 0;
    _audioFileStreamID = nil;
    _playedTime = 0;
    _audioQueue = NULL;
}

@end
