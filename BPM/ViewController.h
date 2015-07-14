//
//  ViewController.h
//  BPM
//
//  Created by Prajeet Shrestha on 7/9/15.
//  Copyright (c) 2015 EK Solutions Pvt Ltd. All rights reserved.
//
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import "AudioPlayer.h"

@interface ViewController: UIViewController<MPMediaPickerControllerDelegate>

@property (weak, nonatomic) IBOutlet UILabel *beatHolder;

@property (nonatomic) AudioPlayer *audioPlayer;
@property (weak, nonatomic) IBOutlet UISlider *currentTimeSlider;
@property (weak, nonatomic) IBOutlet UIButton *playButton;
@property (weak, nonatomic) IBOutlet UILabel *duration;
@property (weak, nonatomic) IBOutlet UILabel *timeElapsed;

@property BOOL isPaused;
@property BOOL scrubbing;

@property NSTimer *timer;
@property NSTimer *updateTimer;

@property (weak, nonatomic) IBOutlet UILabel *beatCounter;
@property (weak, nonatomic) IBOutlet UIImageView *bulb;




@end

