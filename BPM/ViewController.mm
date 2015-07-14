#import "ViewController.h"
#include "SuperpoweredDecoder.h"
#include "SuperpoweredAdvancedAudioPlayer.h"
#include "SuperpoweredSimple.h"
#include "SuperpoweredRecorder.h"
#include "SuperpoweredTimeStretching.h"
#include "SuperpoweredAudioBuffers.h"
#include "SuperpoweredAnalyzer.h"
#include "SuperpoweredMixer.h"
#include "SuperpoweredIOSAudioOutput.h"
#import <stdlib.h>
#import <pthread.h>

#define HEADROOM_DECIBEL 3.0f
static const float headroom = powf(10.0f, -HEADROOM_DECIBEL * 0.025);

@implementation ViewController {
    SuperpoweredAdvancedAudioPlayer *player;
    SuperpoweredIOSAudioOutput *output;
    unsigned char activeFx;
    float *stereoBuffer, crossValue, volA, volB;
    unsigned int lastSamplerate;
    pthread_mutex_t mutex;
    NSURL *audioFileLocation;
    float bpmOfSong;
    float startGrid;
    int beatCount;
    int beatTracker;
    NSTimer *displayTimer;
    float gap;

}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.bulb.hidden = YES;
    beatCount = 0;
    if (posix_memalign((void **)&stereoBuffer, 16, 4096 + 128) != 0) abort(); // Allocating memory, aligned to 16.
    {
        self.beatHolder.text = @"";
    }
}
- (void)displayMediaPicker {
    MPMediaPickerController *picker = [[MPMediaPickerController alloc] initWithMediaTypes:MPMediaTypeMusic];
    [picker setDelegate:self];
    [picker setAllowsPickingMultipleItems:NO];
    picker.prompt = @"Pick a song to process";
    [self presentViewController:picker animated:YES completion:nil];
    picker = nil;
}

- (void)mediaPickerDidCancel:(MPMediaPickerController *)mediaPicker {
    [self dismissViewControllerAnimated:YES completion:nil];
    [self displayMediaPicker];
}

- (void)mediaPicker:(MPMediaPickerController *)mediaPicker didPickMediaItems:(MPMediaItemCollection *)collection {
    [self refresh];
    [self dismissViewControllerAnimated:YES completion:nil];
    NSURL *url = nil;
    MPMediaItem *item = [collection.items objectAtIndex:0];
    if (item) url = [item valueForProperty:@"assetURL"];
    if (url) {
        NSLog(@"Item picked at URL %@",url);
        audioFileLocation = url;
        [self performSelectorInBackground:@selector(processingThread:) withObject:url];

    } else [self displayMediaPicker];
}
- (void)processingThread:(NSURL *)url {
    // Open the input file.
    SuperpoweredDecoder *decoder = new SuperpoweredDecoder();
    const char *openError = decoder->open([[url absoluteString] UTF8String], false, 0, 0);
    if (openError) {
        NSLog(@"open error: %s", openError);
        delete decoder;
        return;
    };
    [self processSongForDecoder:decoder];

}

- (void)refresh {

    bpmOfSong = 0;
    startGrid = 0;
    beatCount = 0;
    beatTracker = 0;
    displayTimer = nil;
    [self.playButton setTitle:@"Play" forState:UIControlStateNormal];
    self.beatCounter.text = @"0.0";
    self.bulb.hidden = YES;
    self.currentTimeSlider.value = 0.0f;
}


-(void)processSongForDecoder:(SuperpoweredDecoder *)decoder {
    int sampleRate = decoder->samplerate;
    double durationSeconds = decoder->durationSeconds;

    SuperpoweredAudiobufferPool *bufferPool = new SuperpoweredAudiobufferPool(4, 1024 * 1024);             // Allow 1 MB max. memory for the buffer pool.

    SuperpoweredOfflineAnalyzer *analyzer = new SuperpoweredOfflineAnalyzer(sampleRate, 0, durationSeconds);

    short int *intBuffer = (short int *)malloc(decoder->samplesPerFrame * 2 * sizeof(short int) + 16384);

    int samplesMultiplier = 4; ////-->> Performance Tradeoff
    while (true) {
        // Decode one frame. samplesDecoded will be overwritten with the actual decoded number of samples.
        unsigned int samplesDecoded = decoder->samplesPerFrame * samplesMultiplier;
        //         NSLog(@"Samples per Frame for decoding->%d->>>", samplesDecoded);
        //         NSLog(@"Sample Position->%lld->>>", decoder->samplePosition);
        if (decoder->decode(intBuffer, &samplesDecoded) != SUPERPOWEREDDECODER_OK) break;
        // Create an input buffer for the analyzer.
        SuperpoweredAudiobufferlistElement inputBuffer;

        bufferPool->createSuperpoweredAudiobufferlistElement(&inputBuffer, decoder->samplePosition, samplesDecoded + 8);

        // Convert the decoded PCM samples from 16-bit integer to 32-bit floating point.
        SuperpoweredShortIntToFloat(intBuffer, bufferPool->floatAudio((&inputBuffer)), samplesDecoded);
        inputBuffer.endSample = samplesDecoded;             // <-- Important!
        analyzer->process(bufferPool->floatAudio(&inputBuffer), samplesDecoded);
    }
    [self freeDecoder:decoder]; //this will free the allocated memory.
    delete bufferPool;
    free(intBuffer);

    unsigned char **averageWaveForm = (unsigned char **)malloc(150 * sizeof(unsigned char *));
    unsigned char **peakWaveForm = (unsigned char **)malloc(150 * sizeof(unsigned char *));
    char **overViewWaveForm = (char **)malloc(durationSeconds * sizeof(char *));
    int *keyIndex = (int *)malloc(sizeof(int));
    int *waveFormSize = (int *)malloc(sizeof(int));
    float *averageDecibel = (float *)malloc(sizeof(float));
    float *loudPartsAverageDecibel = (float *)malloc(sizeof(float));
    float *peakDecibel = (float *)malloc(sizeof(float));
    float *bpm = (float *)malloc(sizeof(float));
    float *beatGridStart = (float *)malloc(sizeof(float));
    analyzer->getresults(averageWaveForm, peakWaveForm, nil, nil, nil, waveFormSize, overViewWaveForm, averageDecibel, loudPartsAverageDecibel, peakDecibel, bpm, beatGridStart, keyIndex);
    self.beatHolder.text = [NSString stringWithFormat:@"BPM: %f",*bpm];
    bpmOfSong = *bpm;
    startGrid = *beatGridStart;

    [self setupAudioPlayer];
    NSLog(@"Beat GridStart %f",*beatGridStart);
    free(averageWaveForm);
    free(peakWaveForm);
    free(overViewWaveForm);
    free(keyIndex);
    free(waveFormSize);
    free(averageDecibel);
    free(loudPartsAverageDecibel);
    free(peakDecibel);
    free(bpm);
    free(beatGridStart);
}

- (void)freeDecoder:(SuperpoweredDecoder *)decoder {
    free(decoder);
}

-(SuperpoweredDecoder *)getSongDecoderForFileURL:(NSURL *)fileURL {
    SuperpoweredDecoder *decoder = new SuperpoweredDecoder();
    const char *openError = decoder->open([fileURL fileSystemRepresentation]);
    if (openError) {
        NSLog(@"%s", openError);
        delete decoder;
        return nil;
    }
    return decoder;
}

- (IBAction)drawMediaPicker:(id)sender {
    [self displayMediaPicker];
}


#pragma mark AudioPlayer Setup
- (void)setupAudioPlayer {

    self.audioPlayer = [[AudioPlayer alloc] init];

    self.timeElapsed.text = @"0:00";
    self.duration.text = [NSString stringWithFormat:@"-%@",
                          [self.audioPlayer timeFormat:[self.audioPlayer getAudioDuration]]];

    [self.audioPlayer initPlayerWithURL:audioFileLocation];
    self.currentTimeSlider.maximumValue = [self.audioPlayer getAudioDuration];
    self.timeElapsed.text = @"0:00";

    self.duration.text = [NSString stringWithFormat:@"-%@",
                          [self.audioPlayer timeFormat:[self.audioPlayer getAudioDuration]]];


}

- (IBAction)playAudioPressed:(id)playButton
{
    if (audioFileLocation != nil) {
        [self.timer invalidate];
        [self.updateTimer invalidate];
        //play audio for the first time or if pause was pressed
        if (!self.isPaused) {
            [self.playButton setTitle:@"Pause" forState:UIControlStateNormal];

            //start a timer to update the time label display
            self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                          target:self
                                                        selector:@selector(updateTime:)
                                                        userInfo:nil
                                                         repeats:YES];

            self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:0.001
                                                                target:self
                                                              selector:@selector(updateBeatCount:)
                                                              userInfo:nil
                                                               repeats:YES];
            [self.audioPlayer playAudio];
            self.isPaused = TRUE;

        } else {
            [self.playButton setTitle:@"Play" forState:UIControlStateNormal];
            [self.audioPlayer pauseAudio];
            self.isPaused = FALSE;
        }
    } else {
        UIAlertView *alert = [[UIAlertView alloc]initWithTitle:@"Select Song!" message:@"Please select the song before you can play" delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles:nil, nil];
        [alert show];
    }
}

- (void)updateBeatCount:(NSTimer *)timer {

    if ([self.audioPlayer getCurrentAudioTime] * 1000 > startGrid) {
        beatCount++;
        gap = 60000/bpmOfSong;
        if (beatCount >= gap    ) {
            self.bulb.hidden = NO;
            NSLog(@"Beat Detected");
            beatCount = 0;
            beatTracker ++;
            self.beatCounter.text = [NSString stringWithFormat:@"%d Beats",beatTracker];
            self.bulb.alpha = 1.0f;
            [UIView animateWithDuration:(gap-20)/1000 animations:^{
                self.bulb.alpha = 0.0f;
            }];

        }
    }
}

- (void)updateTime:(NSTimer *)timer {
    //to don't update every second. When scrubber is mouseDown the the slider will not set
    if (!self.scrubbing) {
        self.currentTimeSlider.value = [self.audioPlayer getCurrentAudioTime];
    }
    self.timeElapsed.text = [NSString stringWithFormat:@"%@",
                             [self.audioPlayer timeFormat:[self.audioPlayer getCurrentAudioTime]]];

    self.duration.text = [NSString stringWithFormat:@"-%@",
                          [self.audioPlayer timeFormat:[self.audioPlayer getAudioDuration] - [self.audioPlayer getCurrentAudioTime]]];
}

/*
 * Sets the current value of the slider/scrubber
 * to the audio file when slider/scrubber is used
 */
- (IBAction)setCurrentTime:(id)scrubber {
    //if scrubbing update the timestate, call updateTime faster not to wait a second and dont repeat it
    [NSTimer scheduledTimerWithTimeInterval:0.01
                                     target:self
                                   selector:@selector(updateTime:)
                                   userInfo:nil
                                    repeats:NO];

    [self.audioPlayer setCurrentAudioTime:self.currentTimeSlider.value];
    self.scrubbing = FALSE;
}

/*
 * Sets if the user is scrubbing right now
 * to avoid slider update while dragging the slider
 */
- (IBAction)userIsScrubbing:(id)sender {
    self.scrubbing = TRUE;
}
@end
