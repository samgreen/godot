/*************************************************************************/
/*  gl_view.mm                                                           */
/*************************************************************************/
/*                       This file is part of:                           */
/*                           GODOT ENGINE                                */
/*                      https://godotengine.org                          */
/*************************************************************************/
/* Copyright (c) 2007-2019 Juan Linietsky, Ariel Manzur.                 */
/* Copyright (c) 2014-2019 Godot Engine contributors (cf. AUTHORS.md)    */
/*                                                                       */
/* Permission is hereby granted, free of charge, to any person obtaining */
/* a copy of this software and associated documentation files (the       */
/* "Software"), to deal in the Software without restriction, including   */
/* without limitation the rights to use, copy, modify, merge, publish,   */
/* distribute, sublicense, and/or sell copies of the Software, and to    */
/* permit persons to whom the Software is furnished to do so, subject to */
/* the following conditions:                                             */
/*                                                                       */
/* The above copyright notice and this permission notice shall be        */
/* included in all copies or substantial portions of the Software.       */
/*                                                                       */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,       */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF    */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.*/
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY  */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,  */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE     */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                */
/*************************************************************************/

#import "gl_view.h"

#include "core/os/keyboard.h"
#include "core/project_settings.h"
#include "os_iphone.h"
#include "servers/audio_server.h"

#import <OpenGLES/EAGLDrawable.h>
#import <QuartzCore/QuartzCore.h>

bool gles3_available = true;
int gl_view_base_fb;
static String keyboard_text;

static GLView *_instance = nil;

static bool video_found_error = false;
static bool video_playing = false;
static CMTime video_current_time;

void _show_keyboard(String);
void _hide_keyboard();
bool _play_video(String, float, String, String);
bool _is_video_playing();
void _pause_video();
void _focus_out_video();
void _unpause_video();
void _stop_video();
CGFloat _points_to_pixels(CGFloat);

void _show_keyboard(String p_existing) {
	keyboard_text = p_existing;
	printf("instance on show is %p\n", _instance);
	[_instance becomeFirstResponder];
};

void _hide_keyboard() {
	printf("instance on hide is %p\n", _instance);
	[_instance resignFirstResponder];
	keyboard_text = "";
};

Rect2 _get_ios_window_safe_area(float p_window_width, float p_window_height) {
	UIEdgeInsets insets = UIEdgeInsetsMake(0, 0, 0, 0);
	if ([_instance respondsToSelector:@selector(safeAreaInsets)]) {
		insets = [_instance safeAreaInsets];
	}
	ERR_FAIL_COND_V(insets.left < 0 || insets.top < 0 || insets.right < 0 || insets.bottom < 0,
			Rect2(0, 0, p_window_width, p_window_height));
	UIEdgeInsets window_insets = UIEdgeInsetsMake(_points_to_pixels(insets.top), _points_to_pixels(insets.left), _points_to_pixels(insets.bottom), _points_to_pixels(insets.right));
	return Rect2(window_insets.left, window_insets.top, p_window_width - window_insets.right - window_insets.left, p_window_height - window_insets.bottom - window_insets.top);
}

bool _play_video(String p_path, float p_volume, String p_audio_track, String p_subtitle_track) {
	p_path = ProjectSettings::get_singleton()->globalize_path(p_path);

	NSString *file_path = [[[NSString alloc] initWithUTF8String:p_path.utf8().get_data()] autorelease];

	_instance.avAsset = [AVAsset assetWithURL:[NSURL fileURLWithPath:file_path]];

	_instance.avPlayerItem = [[AVPlayerItem alloc] initWithAsset:_instance.avAsset];
	[_instance.avPlayerItem addObserver:_instance forKeyPath:@"status" options:0 context:nil];

	_instance.avPlayer = [[AVPlayer alloc] initWithPlayerItem:_instance.avPlayerItem];
	_instance.avPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:_instance.avPlayer];

	[_instance.avPlayer addObserver:_instance forKeyPath:@"status" options:0 context:nil];
	[_instance.avPlayer addObserver:_instance forKeyPath:@"rate" options:NSKeyValueObservingOptionNew context:0];
	[[NSNotificationCenter defaultCenter]
			addObserver:_instance
			   selector:@selector(playerItemDidReachEnd:)
				   name:AVPlayerItemDidPlayToEndTimeNotification
				 object:[_instance.avPlayer currentItem]];

	[_instance.avPlayerLayer setFrame:_instance.bounds];
	[_instance.layer addSublayer:_instance.avPlayerLayer];
	[_instance.avPlayer play];

	AVMediaSelectionGroup *audioGroup = [_instance.avAsset mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicAudible];

	NSMutableArray *allAudioParams = [NSMutableArray array];
	for (id track in audioGroup.options) {
		NSString *language = [[track locale] localeIdentifier];
		NSLog(@"subtitle lang: %@", language);

		if ([language isEqualToString:[NSString stringWithUTF8String:p_audio_track.utf8()]]) {
			AVMutableAudioMixInputParameters *audioInputParams = [AVMutableAudioMixInputParameters audioMixInputParameters];
			[audioInputParams setVolume:p_volume atTime:kCMTimeZero];
			[audioInputParams setTrackID:[track trackID]];
			[allAudioParams addObject:audioInputParams];

			AVMutableAudioMix *audioMix = [AVMutableAudioMix audioMix];
			[audioMix setInputParameters:allAudioParams];

			[_instance.avPlayer.currentItem selectMediaOption:track inMediaSelectionGroup:audioGroup];
			[_instance.avPlayer.currentItem setAudioMix:audioMix];

			break;
		}
	}

	AVMediaSelectionGroup *subtitlesGroup = [_instance.avAsset mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicLegible];
	NSArray *useableTracks = [AVMediaSelectionGroup mediaSelectionOptionsFromArray:subtitlesGroup.options withoutMediaCharacteristics:[NSArray arrayWithObject:AVMediaCharacteristicContainsOnlyForcedSubtitles]];

	for (id track in useableTracks) {
		NSString *language = [[track locale] localeIdentifier];
		NSLog(@"subtitle lang: %@", language);

		if ([language isEqualToString:[NSString stringWithUTF8String:p_subtitle_track.utf8()]]) {
			[_instance.avPlayer.currentItem selectMediaOption:track inMediaSelectionGroup:subtitlesGroup];
			break;
		}
	}

	video_playing = true;

	return true;
}

bool _is_video_playing() {
	if (_instance.avPlayer.error) {
		printf("Error during playback\n");
	}
	return (_instance.avPlayer.rate > 0 && !_instance.avPlayer.error);
}

void _pause_video() {
	video_current_time = _instance.avPlayer.currentTime;
	[_instance.avPlayer pause];
	video_playing = false;
}

void _focus_out_video() {
	printf("focus out pausing video\n");
	[_instance.avPlayer pause];
};

void _unpause_video() {
	[_instance.avPlayer play];
	video_playing = true;
};

void _stop_video() {
	[_instance.avPlayer pause];
	[_instance.avPlayerLayer removeFromSuperlayer];
	_instance.avPlayer = nil;
	video_playing = false;
}

CGFloat _points_to_pixels(CGFloat points) {
	float pixelPerInch;
	if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
		pixelPerInch = 132;
	} else if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
		pixelPerInch = 163;
	} else {
		pixelPerInch = 160;
	}
	CGFloat pointsPerInch = 72.0;
	return (points / pointsPerInch * pixelPerInch);
}

@interface GLView ()

@property(nonatomic, strong) NSMutableArray *activeTouches;

@end

@implementation GLView

@synthesize animationInterval;

// Implement this to override the default layer class (which is [CALayer class]).
// We do this so that our view will be backed by a layer that is capable of OpenGL ES rendering.
+ (Class)layerClass {
	return [CAEAGLLayer class];
}

//The GL view is stored in the nib file. When it's unarchived it's sent -initWithCoder:
- (id)initWithCoder:(NSCoder *)coder {
	if (self = [super initWithCoder:coder]) {
		[self setUp];
	}
	return self;
}

- (id)initWithFrame:(CGRect)frame {
	if (self = [super initWithFrame:frame]) {
		[self setUp];
	}
	return self;
}

- (void)setUp {
	_instance = self;

	self.activeTouches = [[NSMutableArray alloc] initWithCapacity:10];

	active = NO;

	// Get our backing layer
	CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;

	// Configure it so that it is opaque, does not retain the contents of the backbuffer when displayed, and uses RGBA8888 color.
	eaglLayer.opaque = YES;
	eaglLayer.drawableProperties = [NSDictionary
			dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:FALSE],
			kEAGLDrawablePropertyRetainedBacking,
			kEAGLColorFormatRGBA8,
			kEAGLDrawablePropertyColorFormat,
			nil];

	// Create our EAGLContext, and if successful make it current and create our framebuffer.
	context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];

	if (!context || ![EAGLContext setCurrentContext:context] || ![self createFramebuffer]) {
		context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
		gles3_available = false;
		if (!context || ![EAGLContext setCurrentContext:context] || ![self createFramebuffer]) {
			[self release];
			return nil;
		}
	}

	// Default the animation interval to 1/60th of a second.
	animationInterval = 1.0 / 60.0;

	self.multipleTouchEnabled = YES;
	self.autocorrectionType = UITextAutocorrectionTypeNo;

	printf("******** adding observer for sound routing changes\n");
	[[NSNotificationCenter defaultCenter]
			addObserver:self
			   selector:@selector(audioRouteChangeListenerCallback:)
				   name:AVAudioSessionRouteChangeNotification
				 object:nil];

	printf("******** adding observer for keyboard show/hide\n");
	[[NSNotificationCenter defaultCenter]
			addObserver:self
			   selector:@selector(keyboardOnScreen:)
				   name:UIKeyboardDidShowNotification
				 object:nil];
	[[NSNotificationCenter defaultCenter]
			addObserver:self
			   selector:@selector(keyboardHidden:)
				   name:UIKeyboardDidHideNotification
				 object:nil];
}

// Stop animating and release resources when they are no longer needed.
- (void)dealloc {
	[self stopAnimation];

	if ([EAGLContext currentContext] == context) {
		[EAGLContext setCurrentContext:nil];
	}

	[context release];
	context = nil;

	[super dealloc];
}

- (id<GLViewDelegate>)delegate {
	return delegate;
}

// Update the delegate, and if it needs a -setupView: call, set our internal flag so that it will be called.
- (void)setDelegate:(id<GLViewDelegate>)d {
	delegate = d;
}

@synthesize useCADisplayLink;

// If our view is resized, we'll be asked to layout subviews.
// This is the perfect opportunity to also update the framebuffer so that it is
// the same size as our display area.

- (void)layoutSubviews {
	//printf("HERE\n");
	[EAGLContext setCurrentContext:context];
	[self destroyFramebuffer];
	[self createFramebuffer];
	[self drawView];
	[self drawView];
}

- (BOOL)createFramebuffer {
	// Generate IDs for a framebuffer object and a color renderbuffer
	UIScreen *mainscr = [UIScreen mainScreen];
	printf("******** screen size %i, %i\n", (int)mainscr.currentMode.size.width, (int)mainscr.currentMode.size.height);
	self.contentScaleFactor = mainscr.nativeScale;

	glGenFramebuffersOES(1, &viewFramebuffer);
	glGenRenderbuffersOES(1, &viewRenderbuffer);

	glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);
	glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);
	// This call associates the storage for the current render buffer with the EAGLDrawable (our CAEAGLLayer)
	// allowing us to draw into a buffer that will later be rendered to screen wherever the layer is (which corresponds with our view).
	[context renderbufferStorage:GL_RENDERBUFFER_OES fromDrawable:(id<EAGLDrawable>)self.layer];
	glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_RENDERBUFFER_OES, viewRenderbuffer);

	glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &backingWidth);
	glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &backingHeight);

	// For this sample, we also need a depth buffer, so we'll create and attach one via another renderbuffer.
	glGenRenderbuffersOES(1, &depthRenderbuffer);
	glBindRenderbufferOES(GL_RENDERBUFFER_OES, depthRenderbuffer);
	glRenderbufferStorageOES(GL_RENDERBUFFER_OES, GL_DEPTH_COMPONENT16_OES, backingWidth, backingHeight);
	glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_DEPTH_ATTACHMENT_OES, GL_RENDERBUFFER_OES, depthRenderbuffer);

	if (glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES) != GL_FRAMEBUFFER_COMPLETE_OES) {
		NSLog(@"failed to make complete framebuffer object %x", glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES));
		return NO;
	}

	if (OS::get_singleton()) {
		OS::VideoMode vm;
		vm.fullscreen = true;
		vm.width = backingWidth;
		vm.height = backingHeight;
		vm.resizable = false;
		OS::get_singleton()->set_video_mode(vm);
		OSIPhone::get_singleton()->set_base_framebuffer(viewFramebuffer);
	};
	gl_view_base_fb = viewFramebuffer;

	return YES;
}

// Clean up any buffers we have allocated.
- (void)destroyFramebuffer {
	glDeleteFramebuffersOES(1, &viewFramebuffer);
	viewFramebuffer = 0;
	glDeleteRenderbuffersOES(1, &viewRenderbuffer);
	viewRenderbuffer = 0;

	if (depthRenderbuffer) {
		glDeleteRenderbuffersOES(1, &depthRenderbuffer);
		depthRenderbuffer = 0;
	}
}

- (void)startAnimation {
	if (active)
		return;

	active = YES;

	printf("start animation!\n");
	if (useCADisplayLink) {
		displayLink = [CADisplayLink displayLinkWithTarget:self
												  selector:@selector(drawView)];

		// Approximate frame rate: assumes device refreshes at 60 fps.
		// Note that newer iOS devices are 120Hz screens
		displayLink.frameInterval = (int)floor(animationInterval * 60.0f);

		// Setup DisplayLink in main thread
		[displayLink addToRunLoop:[NSRunLoop currentRunLoop]
						  forMode:NSRunLoopCommonModes];
	} else {
		animationTimer = [NSTimer scheduledTimerWithTimeInterval:animationInterval
														  target:self
														selector:@selector(drawView)
														userInfo:nil
														 repeats:YES];
	}

	if (video_playing) {
		_unpause_video();
	}
}

- (void)stopAnimation {
	if (!active)
		return;

	active = NO;
	printf("******** stop animation!\n");

	if (useCADisplayLink) {
		[displayLink invalidate];
		displayLink = nil;
	} else {
		[animationTimer invalidate];
		animationTimer = nil;
	}

	if (video_playing) {
		// save position
	}
}

- (void)setAnimationInterval:(NSTimeInterval)interval {
	animationInterval = interval;
	if ((useCADisplayLink && displayLink) || (!useCADisplayLink && animationTimer)) {
		[self stopAnimation];
		[self startAnimation];
	}
}

// Updates the OpenGL view when the timer fires
- (void)drawView {
	if (useCADisplayLink) {
		// Pause the CADisplayLink to avoid recursion
		[displayLink setPaused:YES];

		// Process all input events
		while (CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, TRUE) == kCFRunLoopRunHandledSource)
			;

		// We are good to go, resume the CADisplayLink
		[displayLink setPaused:NO];
	}

	if (!active) {
		printf("draw view not active!\n");
		return;
	}

	// Make sure that you are drawing to the current context
	[EAGLContext setCurrentContext:context];

	// If our drawing delegate needs to have the view setup, then call -setupView: and flag that it won't need to be called again.
	if ([self.delegate respondsToSelector:@selector(setupView:)] && !delegateSetup) {
		[delegate setupView:self];
		delegateSetup = YES;
	}

	glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);

	[delegate drawView:self];

	glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);
	[context presentRenderbuffer:GL_RENDERBUFFER_OES];

#ifdef DEBUG_ENABLED
	GLenum err = glGetError();
	if (err)
		NSLog(@"%x (gl) error", err);
#endif
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
	UITouch *touch = [touches anyObject];

	[self.activeTouches addObject:touch];

	CGPoint touchPoint = [self scaledPoint:[touch locationInView:self]];
	OSIPhone::get_singleton()->touch_press([self.activeTouches indexOfObject:touch], touchPoint.x, touchPoint.y, true, touch.tapCount > 1);
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
	UITouch *touch = [touches anyObject];

	CGPoint touchPoint = [self scaledPoint:[touch locationInView:self]];
	CGPoint previousPoint = [self scaledPoint:[touch previousLocationInView:self]];
	OSIPhone::get_singleton()->touch_drag([self.activeTouches indexOfObject:touch], previousPoint.x, previousPoint.y, touchPoint.x, touchPoint.y);
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
	UITouch *touch = [touches anyObject];

	CGPoint touchPoint = [self scaledPoint:[touch locationInView:self]];
	OSIPhone::get_singleton()->touch_press([self.activeTouches indexOfObject:touch], touchPoint.x * self.contentScaleFactor, touchPoint.y * self.contentScaleFactor, false, false);

	[self.activeTouches removeObject:touch];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
	UITouch *touch = [touches anyObject];

	OSIPhone::get_singleton()->touches_cancelled();

	[self.activeTouches removeObject:touch];
};

- (CGPoint)scaledPoint:(CGPoint)point {
	return CGPointMake(point.x * self.contentScaleFactor, point.y * self.contentScaleFactor);
}

- (BOOL)canBecomeFirstResponder {
	return YES;
};

- (void)keyboardOnScreen:(NSNotification *)notification {
	NSValue *value = notification.userInfo[UIKeyboardFrameEndUserInfoKey];
	CGRect frame = [value CGRectValue];
	const CGFloat kScaledHeight = _points_to_pixels(frame.size.height);
	OSIPhone::get_singleton()->set_virtual_keyboard_height(kScaledHeight);
}

- (void)keyboardHidden:(NSNotification *)notification {
	OSIPhone::get_singleton()->set_virtual_keyboard_height(0);
}

- (void)deleteBackward {
	if (keyboard_text.length())
		keyboard_text.erase(keyboard_text.length() - 1, 1);
	OSIPhone::get_singleton()->key(KEY_BACKSPACE, true);
};

- (BOOL)hasText {
	return keyboard_text.length() ? YES : NO;
};

- (void)insertText:(NSString *)p_text {
	String character;
	character.parse_utf8([p_text UTF8String]);
	keyboard_text = keyboard_text + character;
	OSIPhone::get_singleton()->key(character[0] == 10 ? KEY_ENTER : character[0], true);
	printf("inserting text with character %lc\n", (CharType)character[0]);
};

- (void)audioRouteChangeListenerCallback:(NSNotification *)notification {
	printf("*********** route changed!\n");
	NSDictionary *interuptionDict = notification.userInfo;

	NSInteger routeChangeReason = [[interuptionDict valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];

	switch (routeChangeReason) {

		case AVAudioSessionRouteChangeReasonNewDeviceAvailable: {
			NSLog(@"AVAudioSessionRouteChangeReasonNewDeviceAvailable");
			NSLog(@"Headphone/Line plugged in");
		}; break;

		case AVAudioSessionRouteChangeReasonOldDeviceUnavailable: {
			NSLog(@"AVAudioSessionRouteChangeReasonOldDeviceUnavailable");
			NSLog(@"Headphone/Line was pulled. Resuming video play....");
			if (_is_video_playing()) {

				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
					[self.avPlayer play]; // NOTE: change this line according your current player implementation
					NSLog(@"resumed play");
				});
			};
		}; break;

		case AVAudioSessionRouteChangeReasonCategoryChange: {
			// called at start - also when other audio wants to play
			NSLog(@"AVAudioSessionRouteChangeReasonCategoryChange");
		}; break;
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (object == self.avPlayerItem && [keyPath isEqualToString:@"status"]) {
		if (self.avPlayerItem.status == AVPlayerStatusFailed || self.avPlayer.status == AVPlayerStatusFailed) {
			_stop_video();
			video_found_error = true;
		}

		if (self.avPlayer.status == AVPlayerStatusReadyToPlay &&
				self.avPlayerItem.status == AVPlayerItemStatusReadyToPlay &&
				CMTIME_COMPARE_INLINE(video_current_time, ==, kCMTimeZero)) {

			[self.avPlayer seekToTime:video_current_time];
			video_current_time = kCMTimeZero;
		}
	}

	if (object == self.avPlayer && [keyPath isEqualToString:@"rate"]) {
		NSLog(@"Player playback rate changed: %.5f", self.avPlayer.rate);

		if (_is_video_playing() && self.avPlayer.rate == 0.0 && !self.avPlayer.error) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
				[self.avPlayer play]; // NOTE: change this line according your current player implementation
				NSLog(@"resumed play");
			});

			NSLog(@" . . . PAUSED (or just started)");
		}
	}
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
	_stop_video();
}

@end
