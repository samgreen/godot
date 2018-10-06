/*************************************************************************/
/*  ios.mm                                                               */
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

#include "ios.h"

#import <UIKit/UIKit.h>
#import <StoreKit/StoreKit.h>

void iOS::_bind_methods() {

	ClassDB::bind_method(D_METHOD("get_rate_url", "app_id"), &iOS::get_rate_url);
	ClassDB::bind_method(D_METHOD("show_store_rating_ui"), &iOS::show_store_rating_ui);
};

void iOS::alert(const char *p_alert, const char *p_title) {
	NSString *titleString = [NSString stringWithUTF8String:p_title];
	NSString *messageString = [NSString stringWithUTF8String:p_alert];

	// Create an alert controller with an OK button for these strings
	UIAlertController *controller = [UIAlertController alertControllerWithTitle:titleString
																		message:messageString
																 preferredStyle:UIAlertControllerStyleAlert];
	UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
	[controller addAction:okAction];

	// Finally present the alert
	[[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:controller
																			  animated:YES
																			completion:nil];
}

String iOS::get_rate_url(int p_app_id) const {
	String rate_url = "itms-apps://itunes.apple.com/WebObjects/MZStore.woa/wa/viewContentsUserReviews?id=APP_ID&onlyLatestVersion=true&pageNumber=0&sortOrdering=1&type=Purple+Software";
	rate_url = rate_url.replace("APP_ID", String::num(p_app_id));
	printf("returning rate url %ls\n", rate_url.c_str());
	return rate_url;
};

void iOS::show_store_rating_ui() {
	[SKStoreReviewController requestReview];
}

extern "C" {

int add_path(int p_argc, char **p_args) {

	NSString *str = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"godot_path"];
	if (!str)
		return p_argc;

	p_args[p_argc++] = (char *)"--path";
	p_args[p_argc++] = (char *)[[str copy] cStringUsingEncoding:NSUTF8StringEncoding];
	p_args[p_argc] = NULL;

	return p_argc;
};

int add_cmdline(int p_argc, char **p_args) {

	NSArray *arr = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"godot_cmdline"];
	if (!arr)
		return p_argc;

	for (id value in arr) {

		NSString *string = value;
		if (![string isKindOfClass:NSString.class])
			continue;

		p_args[p_argc++] = (char *)[[string copy] cStringUsingEncoding:NSUTF8StringEncoding];
	};

	p_args[p_argc] = NULL;

	return p_argc;
};
}; // extern "C"

iOS::iOS(){};
