//
//  ViewController.h
//  iBrogue_iPad
//
//  Created by Seth Howard on 2/22/13.
//  Copyright (c) 2013 Seth howard. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Rogue.h"

@class Viewport, ViewController;

// Lazy accessors. Used in the C bridge.
extern Viewport *theMainDisplay;
extern ViewController *viewController;

@interface ViewController : UIViewController

struct iBTouch {
    UITouchPhase phase;
    CGPoint location;
};
typedef struct iBTouch iBTouch;

/// Used to trigger seed button for the UI.
@property (nonatomic, readonly, getter = isSeedKeyDown) BOOL seedKeyDown;
/// General catch all for events. Will return TRUE if there are touch or key events.
@property (nonatomic, readonly) BOOL hasEvent;
/// TRUE if the user has touched the screen and an event is queued up.
@property (nonatomic, readonly) BOOL hasTouchEvent;
/// TRUE if an user action has translated into a key event.
@property (nonatomic, readonly) BOOL hasKeyEvent;

/**
 * Setter for Game Events that require action by the ViewController. This may be opening or closing menus or creating transitions, blocking input, etc.
 * 
 * @params brogueGameEvent An event that requires the VC to take action.
 */
- (void)setBrogueGameEvent:(BrogueGameEvent)brogueGameEvent;

// Touches

/**
 * Getter for queued touch events.
 *
 * @params index Index of the touch.
 * @return An iBTouch struct object containing touch info.
 */
- (iBTouch)getTouchAtIndex:(uint)index;

/**
 * Removed queued touch events at a particular index.
 *
 * @params index Index of the touch.
 */
- (void)removeTouchAtIndex:(uint)index;

/**
 * Removes key stroke event at the head of the queue.
 *
 * @return The key character.
 */
- (char)dequeKeyStroke;

// Settings... If there were more I'd suggest their own class.

/**
 * Turn on the pinch gesture that hides the user controls.
 */
- (void)turnOnPinchGesture;

/**
 * Turn off the pinch gesture that hides the user controls.
 */
- (void)turnOffPinchGesture;

@end