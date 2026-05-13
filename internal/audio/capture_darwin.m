// capture_darwin.m — ScreenCaptureKit audio capture for macOS 13+.
// Exposes a C API consumed by capture_darwin.go via cgo.

#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <CoreMedia/CoreMedia.h>
#import <AudioToolbox/AudioToolbox.h>
#import <os/lock.h>

// --- Ring buffer ---
// Power-of-2 ring buffer for passing float32 PCM samples from the
// ScreenCaptureKit callback (arbitrary dispatch queue) to Go (~30Hz poll).

#define RING_BITS 16
#define RING_SIZE (1 << RING_BITS)  // 65536 samples (~1.5s at 44.1kHz)
#define RING_MASK (RING_SIZE - 1)

static float g_ring[RING_SIZE];
static uint32_t g_wpos = 0;
static uint32_t g_rpos = 0;
static os_unfair_lock g_lock = OS_UNFAIR_LOCK_INIT;

// --- Stream output delegate ---

API_AVAILABLE(macos(13.0))
@interface NPAudioDelegate : NSObject <SCStreamOutput>
@end

@implementation NPAudioDelegate

- (void)stream:(SCStream *)stream
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
                   ofType:(SCStreamOutputType)type {
    if (type != SCStreamOutputTypeAudio) return;

    AudioBufferList abl;
    CMBlockBufferRef blockBuf = NULL;
    OSStatus status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
        sampleBuffer, NULL, &abl, sizeof(abl), NULL, NULL,
        kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
        &blockBuf);
    if (status != noErr) return;

    float *samples = (float *)abl.mBuffers[0].mData;
    uint32_t count = abl.mBuffers[0].mDataByteSize / sizeof(float);

    os_unfair_lock_lock(&g_lock);
    for (uint32_t i = 0; i < count; i++) {
        g_ring[g_wpos & RING_MASK] = samples[i];
        g_wpos++;
    }
    os_unfair_lock_unlock(&g_lock);

    if (blockBuf) CFRelease(blockBuf);
}

@end

// --- Global state ---

static SCStream *g_stream API_AVAILABLE(macos(13.0)) = nil;
static NPAudioDelegate *g_delegate API_AVAILABLE(macos(13.0)) = nil;

// --- C API ---

int audio_capture_available(void) {
    if (@available(macOS 13.0, *)) {
        return 1;
    }
    return 0;
}

int audio_capture_start(const char *bundle_id) {
    if (@available(macOS 13.0, *)) {
        __block int result = -1;
        NSString *bid = [NSString stringWithUTF8String:bundle_id];
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);

        [SCShareableContent getShareableContentExcludingDesktopWindows:YES
            onScreenWindowsOnly:NO
            completionHandler:^(SCShareableContent *content, NSError *error) {
                if (error || !content) {
                    dispatch_semaphore_signal(sem);
                    return;
                }

                SCRunningApplication *targetApp = nil;
                for (SCRunningApplication *app in content.applications) {
                    if ([app.bundleIdentifier isEqualToString:bid]) {
                        targetApp = app;
                        break;
                    }
                }
                if (!targetApp) {
                    dispatch_semaphore_signal(sem);
                    return;
                }

                SCDisplay *display = content.displays.firstObject;
                if (!display) {
                    dispatch_semaphore_signal(sem);
                    return;
                }

                // Include only the target app by excluding everything else.
                NSMutableArray *excluded = [NSMutableArray array];
                for (SCRunningApplication *app in content.applications) {
                    if (![app.bundleIdentifier isEqualToString:bid]) {
                        [excluded addObject:app];
                    }
                }
                SCContentFilter *filter = [[SCContentFilter alloc]
                    initWithDisplay:display
                    excludingApplications:excluded
                    exceptingWindows:@[]];

                SCStreamConfiguration *config = [[SCStreamConfiguration alloc] init];
                config.capturesAudio = YES;
                config.excludesCurrentProcessAudio = YES;
                config.channelCount = 1;
                config.sampleRate = 44100;
                // Minimize video overhead — we only want audio.
                config.width = 1;
                config.height = 1;
                config.minimumFrameInterval = CMTimeMake(1, 1);

                g_delegate = [[NPAudioDelegate alloc] init];
                g_stream = [[SCStream alloc] initWithFilter:filter
                    configuration:config
                    delegate:nil];

                NSError *addErr = nil;
                [g_stream addStreamOutput:g_delegate
                    type:SCStreamOutputTypeAudio
                    sampleHandlerQueue:dispatch_get_global_queue(
                        QOS_CLASS_USER_INTERACTIVE, 0)
                    error:&addErr];
                if (addErr) {
                    g_stream = nil;
                    g_delegate = nil;
                    dispatch_semaphore_signal(sem);
                    return;
                }

                [g_stream startCaptureWithCompletionHandler:^(NSError *startErr) {
                    if (!startErr) {
                        result = 0;
                    }
                    dispatch_semaphore_signal(sem);
                }];
            }];

        dispatch_semaphore_wait(sem,
            dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
        return result;
    }
    return -1;
}

void audio_capture_stop(void) {
    if (@available(macOS 13.0, *)) {
        if (g_stream) {
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            [g_stream stopCaptureWithCompletionHandler:^(NSError *err) {
                (void)err;
                dispatch_semaphore_signal(sem);
            }];
            dispatch_semaphore_wait(sem,
                dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
            g_stream = nil;
            g_delegate = nil;
        }
    }
}

int audio_capture_read(float *buf, int max_samples) {
    os_unfair_lock_lock(&g_lock);
    uint32_t avail = g_wpos - g_rpos;
    if (avail > RING_SIZE) {
        // Writer lapped reader — skip to latest data.
        g_rpos = g_wpos - RING_SIZE;
        avail = RING_SIZE;
    }
    uint32_t to_read = avail < (uint32_t)max_samples
        ? avail : (uint32_t)max_samples;
    for (uint32_t i = 0; i < to_read; i++) {
        buf[i] = g_ring[g_rpos & RING_MASK];
        g_rpos++;
    }
    os_unfair_lock_unlock(&g_lock);
    return (int)to_read;
}
