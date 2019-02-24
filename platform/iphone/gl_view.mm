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

#import "core/project_settings.h"
#import "os_iphone.h"
#import "servers/audio_server.h"

#import <OpenGLES/EAGLDrawable.h>

bool gles3_available = true;
int gl_view_base_fb;

static GLView *_instance = nil;

CGFloat _points_to_pixels(CGFloat);

void _show_keyboard(String p_existing) {
	keyboard_text = p_existing;
	NSLog(@"Show keyboard");
	[_instance becomeFirstResponder];
};

void _hide_keyboard() {
	NSLog(@"Hide keyboard and clear text");
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

OS::VideoMode _get_video_mode() {
	int backingWidth;
	int backingHeight;
	glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES,
			GL_RENDERBUFFER_WIDTH_OES, &backingWidth);
	glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES,
			GL_RENDERBUFFER_HEIGHT_OES, &backingHeight);

	OS::VideoMode vm;
	vm.fullscreen = true;
	vm.width = backingWidth;
	vm.height = backingHeight;
	vm.resizable = false;
	return vm;
}

@interface GLView ()

@property(nonatomic, strong) CADisplayLink *displayLink;
@property(nonatomic, assign) BOOL useCADisplayLink;

@end

@implementation GLView

@synthesize animationInterval = _animationInterval;

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

	self.useCADisplayLink = bool(GLOBAL_DEF("display.iOS/use_cadisplaylink", true)) ? YES : NO;
	printf("CADisplayLink is %s. From setting 'display.iOS/use_cadisplaylink'\n", self.useCADisplayLink ? "enabled" : "disabled");

	self.active = NO;
	self.multipleTouchEnabled = YES;
	self.autocorrectionType = UITextAutocorrectionTypeNo;

	// Get our backing layer
	CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;

	// Configure it so that it is opaque, does not retain the contents of the backbuffer when displayed, and uses RGBA8888 color.
	eaglLayer.opaque = YES;
	eaglLayer.drawableProperties = @{ kEAGLDrawablePropertyRetainedBacking : @(NO),
		kEAGLDrawablePropertyColorFormat : kEAGLColorFormatRGBA8 };

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
}

- (void)dealloc {
	[self stopAnimation];

	if ([EAGLContext currentContext] == context) {
		[EAGLContext setCurrentContext:nil];
	}

	[context release];
	context = nil;

	[super dealloc];
}

- (void)layoutSubviews {
	[EAGLContext setCurrentContext:context];
	[self destroyFramebuffer];
	[self createFramebuffer];
	[self drawView];
	[self drawView];
}

- (BOOL)createFramebuffer {
	// Generate IDs for a framebuffer object and a color renderbuffer
	glGenFramebuffersOES(1, &viewFramebuffer);
	glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);

	// Next the render backing store
	[self createRenderBuffer];

	// For this sample, we also need a depth buffer, so we'll create and attach one via another renderbuffer.
	[self createDepthBuffer];

	if (glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES) != GL_FRAMEBUFFER_COMPLETE_OES) {
		printf("failed to make complete framebuffer object %x", glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES));
		return NO;
	}

	if (OS::get_singleton()) {
		OSIPhone::get_singleton()->set_base_framebuffer(viewFramebuffer);

		OS::VideoMode vm;
		vm.fullscreen = true;
		vm.resizable = false;
		glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &vm.width);
		glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &vm.height);
		OS::get_singleton()->set_video_mode(vm);
	}

	// Save the gl reference to the frame buffer
	gl_view_base_fb = viewFramebuffer;

	return YES;
}

- (void)createRenderBuffer {

	// Generate a gl render buffer and make it active
	glGenRenderbuffersOES(1, &viewRenderbuffer);
	glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);

	// This call associates the storage for the current render buffer with the EAGLDrawable (our CAEAGLLayer)
	// allowing us to draw into a buffer that will later be rendered to screen wherever the layer is (which corresponds with our view).
	[context renderbufferStorage:GL_RENDERBUFFER_OES
					fromDrawable:(id<EAGLDrawable>)self.layer];
	glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_RENDERBUFFER_OES, viewRenderbuffer);

	glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES,
			GL_RENDERBUFFER_WIDTH_OES, &backingWidth);
	glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES,
			GL_RENDERBUFFER_HEIGHT_OES, &backingHeight);
}

- (void)createDepthBuffer {
	glGenRenderbuffersOES(1, &depthRenderbuffer);
	glBindRenderbufferOES(GL_RENDERBUFFER_OES, depthRenderbuffer);
	glRenderbufferStorageOES(GL_RENDERBUFFER_OES, GL_DEPTH_COMPONENT16_OES, backingWidth, backingHeight);
	glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_DEPTH_ATTACHMENT_OES, GL_RENDERBUFFER_OES, depthRenderbuffer);
}

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
	// Already active?
	if (self.isActive) return;

	self.active = YES;

	printf("start animation!\n");

	if (self.useCADisplayLink) {

		// Create a display link and try and grab the fatest refresh rate
		_displayLink = [CADisplayLink displayLinkWithTarget:self
												   selector:@selector(drawView)];
		if ([_displayLink respondsToSelector:@selector(preferredFramesPerSecond)]) {
			_displayLink.preferredFramesPerSecond = 0;
			// We could potentially check the display link's maximumFPS here.
			// If it supports 120 we could force the preferredFPS to that.
			// Currently that the's only way to drive a game at 120Hz
		} else {
			// Approximate frame rate: assumes device refreshes at 60 fps.
			// Note that newer iOS devices are 120Hz screens
			_displayLink.frameInterval = 1;
		}

		// Setup DisplayLink in main thread
		[_displayLink addToRunLoop:[NSRunLoop currentRunLoop]
						   forMode:NSRunLoopCommonModes];
	} else {
		// This is an extremely terrible way to animate. Very low resolution with lots
		// of drift. You would be lucky to have this called every 16ms
		animationTimer = [NSTimer scheduledTimerWithTimeInterval:self.animationInterval
														  target:self
														selector:@selector(drawView)
														userInfo:nil
														 repeats:YES];
	}

	// if (video_playing) {
	// 	_unpause_video();
	// }
}

- (void)stopAnimation {
	if (!self.isActive) return;

	self.active = NO;
	printf("stop animation!\n");

	if (self.useCADisplayLink) {
		[_displayLink invalidate];
		_displayLink = nil;
	} else {
		[animationTimer invalidate];
		animationTimer = nil;
	}

	// if (video_playing) {
	// 	_pause_video();
	// }
}

- (void)setAnimationInterval:(NSTimeInterval)interval {

	_animationInterval = interval;

	if (self.isActive) {
		[self stopAnimation];
	}
	[self startAnimation];
}

- (NSTimeInterval)animationInterval {
	return _animationInterval;
}

- (void)drawView {
	if (!self.isActive) {
		printf("Attempted to drawView while inactive!\n");
		return;
	}

	// Make sure that you are drawing to the current context
	[EAGLContext setCurrentContext:context];

	// If our drawing delegate needs to have the view setup, then call -setupView: and flag that it won't need to be called again.
	if (!self.isSetUpComplete && [self.delegate respondsToSelector:@selector(setupView:)]) {
		[self.delegate setupView:self];
		self.setUpComplete = YES;
	}

	glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);
	[self.delegate drawView:self];

	glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);
	[context presentRenderbuffer:GL_RENDERBUFFER_OES];

#ifdef DEBUG_ENABLED
	GLenum err = glGetError();
	if (err)
		NSLog(@"%x (gl) error", err);
#endif
}

- (BOOL)canBecomeFirstResponder {
	return YES;
}

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
}

- (BOOL)hasText {
	return keyboard_text.length() ? YES : NO;
}

- (void)insertText:(NSString *)p_text {
	String character;
	character.parse_utf8([p_text UTF8String]);
	keyboard_text = keyboard_text + character;
	OSIPhone::get_singleton()->key(character[0] == 10 ? KEY_ENTER : character[0], true);
	printf("inserting text with character %lc\n", (CharType)character[0]);
};

@end
