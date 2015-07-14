//
//  AudioPlayer.h
//  BPM
//
//  Created by Prajeet Shrestha on 7/14/15.
//  Copyright (c) 2015 EK Solutions Pvt Ltd. All rights reserved.
//
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface AudioPlayer : UIViewController
@property (nonatomic, retain) AVAudioPlayer *audioPlayer;

// Public methods
- (void)initPlayerWithURL:(NSURL *)url;
- (void)playAudio;
- (void)pauseAudio;
- (void)setCurrentAudioTime:(float)value;
- (float)getAudioDuration;
- (NSString*)timeFormat:(float)value;
- (NSTimeInterval)getCurrentAudioTime;

@end
