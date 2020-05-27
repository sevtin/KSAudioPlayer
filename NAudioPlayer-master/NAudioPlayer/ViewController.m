//
//  ViewController.m
//  NAudioPlayer
//
//  Created by 泽娄 on 2019/9/22.
//  Copyright © 2019 泽娄. All rights reserved.
//

#import "ViewController.h"
#import "NAudioPlayer.h"

@interface ViewController (){
    NSTimer *progressUpdateTimer;
    NSString *_path;
}

@property (weak, nonatomic) IBOutlet UIButton *playBtn;

@property (weak, nonatomic) IBOutlet UIButton *stopBtn;

@property (weak, nonatomic) IBOutlet UISlider *progressSlider;

@property (weak, nonatomic) IBOutlet UILabel *positionLabel;

@property (nonatomic, strong) NAudioPlayer *player;

@end
/*
 <key>明天，你好</key>
 <string>http://mpge.5nd.com/2010/2010b/2011-07-18/48414/1.mp3</string>
 <key>白狐</key>
 <string>http://mpge.5nd.com/2015/2015-5-6/66943/14.mp3</string>
 <key>天使的翅膀</key>
 <string>http://mpge.5nd.com/2009/2009a/x/24352/1.mp3</string>
 <key>爱如潮水</key>
 <string>http://mpge.5nd.com/2008/z/13621/15.mp3</string>
 <key>老人与海</key>
 <string>http://mpge.5nd.com/2007/h/20075225298269/52989152.mp3</string>
 <key>美丽的神话</key>
 <string>http://mpge.5nd.com/2005/s/2005920/995/3304410.mp3</string>
*/
@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    _progressSlider.value = 0.0;
    _path = [[NSBundle mainBundle] pathForResource:@"309769" ofType:@"mp3"];
}

- (IBAction)handlePlay:(UIButton *)sender
{
    if (_player.status == NAudioPlayerStatusPlaying || _player.status == NAudioPlayerStatusWaiting) {
        NSLog(@"暂停");
        [_player pause];
        [_playBtn setTitle:@"Play" forState:(UIControlStateNormal)];
    }else{
        NSLog(@"开始");
        [self createPlayer];
        [_player play];
        [_playBtn setTitle:@"Pause" forState:(UIControlStateNormal)];
    }
}

- (IBAction)handleStop:(UIButton *)sender
{
    if (!_player) {
        NSLog(@"播放器未初始化");
        return;
    }
    
    if (_player.status == NAudioPlayerStatusWaiting || _player.status == NAudioPlayerStatusPlaying) {
        [_player stop];
    }
}

- (IBAction)handleProgressSlider:(UISlider *)sender
{
    NSLog(@"进度条: %.2f", sender.value);
    double newTime = sender.value * (_player.duration);
    [_player seekToTime:newTime];
}

- (void)updateProgress:(NSTimer *)updatedTimer
{
    if ((_player.bitRate != 0.0) && (_player.duration != 0.0)) {
        double progress = _player.progress;
        double duration = _player.duration;
        if (duration > 0) {
            [_progressSlider setEnabled:YES];
            [_progressSlider setValue:(progress / duration) animated:YES];
            [_positionLabel setText:[NSString stringWithFormat:@"Time Played: %.1f/%.1f seconds", progress, duration]];
        }else{
            [_progressSlider setEnabled:NO];
        }
    }else{
        [_progressSlider setEnabled:NO];
        [_progressSlider setValue:0.0 animated:YES];
        [_positionLabel setText:@"Time Played:"];
    }
}

/// 创建播放器
- (void)createPlayer
{
    if (_player) {
        return;
    }
    
    [self destroyPlayer];
    
    if (!_player) {
        _player = [[NAudioPlayer alloc] initWithFilePath:_path];
        [_player addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    }
    
    /// 进度定时器
    if (!progressUpdateTimer) {
        progressUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self
                                       selector:@selector(updateProgress:)
                                       userInfo:nil
                                       repeats:YES];
    }
    
}

/// 销毁播放器
- (void)destroyPlayer
{
    if (_player){
        NSLog(@"销毁_player");
        [_player stop];
        _player = nil;
    }
}

#pragma mark - status kvo
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (object == _player) {
        if ([keyPath isEqualToString:@"status"]) {
            [self performSelectorOnMainThread:@selector(handleStatusChanged) withObject:nil waitUntilDone:NO];
        }
    }
}

- (void)handleStatusChanged
{
    NSLog(@"_player.status: %lu", (unsigned long)_player.status);
    if (_player.status == NAudioPlayerStatusStopped) {
        [_playBtn setTitle:@"Play" forState:(UIControlStateNormal)];
        [self destroyPlayer]; /// 销毁播放器
    }else if (_player.status == NAudioPlayerStatusPaused){
        [_playBtn setTitle:@"Play" forState:(UIControlStateNormal)];
    }
}

- (void)dealloc
{
    if (progressUpdateTimer) {
        [progressUpdateTimer invalidate];
        progressUpdateTimer = nil;
    }
}

@end
