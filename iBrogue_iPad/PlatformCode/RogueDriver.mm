//
//  RogueDriver.m
//  Brogue
//
//  Created by Brian and Kevin Walker on 12/26/08.
//  Updated for iOS by Seth Howard on 03/01/13
//  Copyright 2012. All rights reserved.
//
//  This file is part of Brogue.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as
//  published by the Free Software Foundation, either version 3 of the
//  License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#include <limits.h>
#include <unistd.h>
#include "CoreFoundation/CoreFoundation.h"
#import "RogueDriver.h"
#import "ViewController.h"
#import "AppDelegate.h"
#include "IncludeGlobals.h"
#include "Rogue.h"
#import "GameCenterManager.h"
#import <QuartzCore/QuartzCore.h>
#import "iRate.h"

#import "MGBenchmark.h"
#import "MGBenchmarkSession.h"

#define kRateScore 3000

#define BROGUE_VERSION	4	// A special version number that's incremented only when
// something about the OS X high scores file structure changes.

// Objective-c Bridge

static CGColorSpaceRef _colorSpace;

short mouseX, mouseY;

@implementation RogueDriver 

+ (id)sharedInstance {
    static RogueDriver *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[RogueDriver alloc] init];
    });
    
    return instance;
}

- (id)init
{
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
        
        if (!_colorSpace) {
            _colorSpace = CGColorSpaceCreateDeviceRGB();
        }
    }
    return self;
}

- (void)applicationDidBecomeActive {
    double delayInSeconds = .5;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        clearCursor();
    });
}

+ (unsigned long)rogueSeed {
    return rogue.seed;
}

@end

//  plotChar: plots inputChar at (xLoc, yLoc) with specified background and foreground colors.
//  Color components are given in ints from 0 to 100.

void plotChar(uchar inputChar,
			  short xLoc, short yLoc,
			  short foreRed, short foreGreen, short foreBlue,
			  short backRed, short backGreen, short backBlue) {
//[MGBenchmark start:@"plot"];
//    @autoreleasepool {
    CGColorRef backColor = nil;
    if (backRed != 0 || backGreen != 0 || backBlue != 0) {
        CGFloat backComponents[] = {(CGFloat)(backRed * .01), (CGFloat)(backGreen * .01), (CGFloat)(backBlue * .01), 1.};
        backColor = CGColorCreate(_colorSpace, backComponents);
    }

    CGColorRef foreColor = nil;
    if (inputChar != ' ') {
  //      if ((foreRed != 0 || foreGreen != 0 || foreBlue != 0) && inputChar != ' ') {
            CGFloat foreComponents[] = {(CGFloat)(foreRed * .01), (CGFloat)(foreGreen * .01), (CGFloat)(foreBlue * .01), 1.};
            foreColor = CGColorCreate(_colorSpace, foreComponents);
  //      }
    }
    

    NSString *uniLetter;
    if (inputChar > 127 && inputChar != 183) {
        uniLetter = [NSString stringWithCharacters:&inputChar length:1];
    }
    
    [theMainDisplay setString:uniLetter withBackgroundColor:backColor letterColor:foreColor atLocationX:xLoc locationY:yLoc withChar:inputChar];
 //   }
    
//    [[MGBenchmark session:@"plot"] total];
//    [MGBenchmark finish:@"plot"];
}

__unused void pausingTimerStartsNow() {
    // unused
}

#pragma mark - input

void clearCursor() {
    rogue.cursorLoc[0] = -1;
    rogue.cursorLoc[1] = -1;
}

// Returns true if the player interrupted the wait with a keystroke; otherwise false.
boolean pauseForMilliseconds(short milliseconds) {
    BOOL hasEvent = NO;
    
    [NSThread sleepForTimeInterval:milliseconds/1000.];
    
    if ([viewController hasEvent]) {
        hasEvent = YES;
    }

	return hasEvent;
}

void nextKeyOrMouseEvent(rogueEvent *returnEvent, __unused boolean textInput, boolean colorsDance) {
	CGPoint event_location;
	short x, y;
    
    for(;;) {
        if (colorsDance) {
            // we should be ok to block here. We don't seem to call pauseForMilli and this at the same time
            // 60Hz
            [NSThread sleepForTimeInterval:0.016667];
            shuffleTerrainColors(3, true);
            commitDraws();
        }
        
        if ([viewController hasKeyEvent]) {
            returnEvent->eventType = KEYSTROKE;
            returnEvent->param1 = [viewController dequeKeyStroke];
            //printf("\nKey pressed: %i", returnEvent->param1);
            returnEvent->param2 = 0;
            returnEvent->controlKey = 0;//([theEvent modifierFlags] & NSControlKeyMask ? 1 : 0);
            returnEvent->shiftKey = 0;//([theEvent modifierFlags] & NSShiftKeyMask ? 1 : 0);
            clearCursor();
            break;
        }
        if ([viewController hasTouchEvent]) {
            iBTouch touch = [viewController getTouchAtIndex:0];
            [viewController removeTouchAtIndex:0];
            UITouchPhase phase = touch.phase;
            
            if (phase != UITouchPhaseCancelled) {
                switch (phase) {
                    case UITouchPhaseBegan:
                    case UITouchPhaseStationary:
                        returnEvent->eventType = MOUSE_DOWN;
                        break;
                    case UITouchPhaseEnded:
                        returnEvent->eventType = MOUSE_UP;
                        break;
                    case UITouchPhaseMoved:
                        returnEvent->eventType = MOUSE_ENTERED_CELL;
                        break;
                    default:
                        break;
                }
                
                event_location = touch.location;
                x = COLS * event_location.x / [theMainDisplay hWindow];
                y = (ROWS * event_location.y / [theMainDisplay vWindow]);
                
                returnEvent->param1 = x;
                returnEvent->param2 = y;
                returnEvent->controlKey = 0;
                returnEvent->shiftKey = 0;
                
                break;
            }
        }
    }
}

#pragma mark - bridge

void setBrogueGameEvent(BrogueGameEvent brogueGameEvent) {
    [viewController setBrogueGameEvent:brogueGameEvent];
}

boolean controlKeyIsDown() {
    if ([viewController isSeedKeyDown]) {
        return 1;
    }
    
    return 0;
}

boolean shiftKeyIsDown() {
    return NO;
}

void submitAchievementForCharString(char *achievementKey) {
    [[GameCenterManager sharedInstance] submitAchievement:[NSString stringWithUTF8String:achievementKey] percentComplete:100.];
}

#pragma mark - OSX->iOS implementation

void initHighScores() {
	NSMutableArray *scoresArray, *textArray, *datesArray;
	short j, theCount;
    
	if ([[NSUserDefaults standardUserDefaults] arrayForKey:@"high scores scores"] == nil
		|| [[NSUserDefaults standardUserDefaults] arrayForKey:@"high scores text"] == nil
		|| [[NSUserDefaults standardUserDefaults] arrayForKey:@"high scores dates"] == nil) {
        
		scoresArray = [NSMutableArray arrayWithCapacity:HIGH_SCORES_COUNT];
		textArray = [NSMutableArray arrayWithCapacity:HIGH_SCORES_COUNT];
		datesArray = [NSMutableArray arrayWithCapacity:HIGH_SCORES_COUNT];
        
		for (j=0; j<HIGH_SCORES_COUNT; j++) {
			[scoresArray addObject:[NSNumber numberWithLong:0]];
			[textArray addObject:[NSString string]];
			[datesArray addObject:[NSDate date]];
		}
        
		[[NSUserDefaults standardUserDefaults] setObject:scoresArray forKey:@"high scores scores"];
		[[NSUserDefaults standardUserDefaults] setObject:textArray forKey:@"high scores text"];
		[[NSUserDefaults standardUserDefaults] setObject:datesArray forKey:@"high scores dates"];
	}
    
	theCount = [[[NSUserDefaults standardUserDefaults] arrayForKey:@"high scores scores"] count];
    
	if (theCount < HIGH_SCORES_COUNT) { // backwards compatibility
		scoresArray = [NSMutableArray arrayWithCapacity:HIGH_SCORES_COUNT];
		textArray = [NSMutableArray arrayWithCapacity:HIGH_SCORES_COUNT];
		datesArray = [NSMutableArray arrayWithCapacity:HIGH_SCORES_COUNT];
        
		[scoresArray setArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"high scores scores"]];
		[textArray setArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"high scores text"]];
		[datesArray setArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"high scores dates"]];
        
		for (j=theCount; j<HIGH_SCORES_COUNT; j++) {
			[scoresArray addObject:[NSNumber numberWithLong:0]];
			[textArray addObject:[NSString string]];
			[datesArray addObject:[NSDate date]];
		}
        
		[[NSUserDefaults standardUserDefaults] setObject:scoresArray forKey:@"high scores scores"];
		[[NSUserDefaults standardUserDefaults] setObject:textArray forKey:@"high scores text"];
		[[NSUserDefaults standardUserDefaults] setObject:datesArray forKey:@"high scores dates"];
	}
    
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// returns the index number of the most recent score
short getHighScoresList(rogueHighScoresEntry returnList[HIGH_SCORES_COUNT]) {
	NSArray *scoresArray, *textArray, *datesArray;
	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"MM/dd/yy"];
    NSDate *mostRecentDate;
	short i, j, maxIndex, mostRecentIndex;
	long maxScore;
	boolean scoreTaken[HIGH_SCORES_COUNT];
    
	// no scores have been taken
	for (i=0; i<HIGH_SCORES_COUNT; i++) {
		scoreTaken[i] = false;
	}
    
	initHighScores();
    
	scoresArray = [[NSUserDefaults standardUserDefaults] arrayForKey:@"high scores scores"];
	textArray = [[NSUserDefaults standardUserDefaults] arrayForKey:@"high scores text"];
	datesArray = [[NSUserDefaults standardUserDefaults] arrayForKey:@"high scores dates"];
    
	mostRecentDate = [NSDate distantPast];
    
	// store each value in order into returnList
	for (i=0; i<HIGH_SCORES_COUNT; i++) {
		// find the highest value that hasn't already been taken
		maxScore = 0; // excludes scores of zero
		for (j=0; j<HIGH_SCORES_COUNT; j++) {
			if (scoreTaken[j] == false && [[scoresArray objectAtIndex:j] longValue] >= maxScore) {
				maxScore = [[scoresArray objectAtIndex:j] longValue];
				maxIndex = j;
			}
		}
		// maxIndex identifies the highest non-taken score
		scoreTaken[maxIndex] = true;
		returnList[i].score = [[scoresArray objectAtIndex:maxIndex] longValue];
		strcpy(returnList[i].description, [[textArray objectAtIndex:maxIndex] cStringUsingEncoding:NSASCIIStringEncoding]);
		strcpy(returnList[i].date, [[dateFormatter stringFromDate:[datesArray objectAtIndex:maxIndex]] cStringUsingEncoding:NSASCIIStringEncoding]);
        
		// if this is the most recent score we've seen so far
		if ([mostRecentDate compare:[datesArray objectAtIndex:maxIndex]] == NSOrderedAscending) {
			mostRecentDate = [datesArray objectAtIndex:maxIndex];
			mostRecentIndex = i;
		}
	}
    
    
	return mostRecentIndex;
}

// saves the high scores entry over the lowest-score entry if it qualifies.
// returns whether the score qualified for the list.
// This function ignores the date passed to it in theEntry and substitutes the current
// date instead.

// TODO: going to assume every save highscore qualifies as an end game screen.

boolean saveHighScore(rogueHighScoresEntry theEntry) {
	NSMutableArray *scoresArray, *textArray, *datesArray;
	NSNumber *newScore;
	NSString *newText;
    
	short j, minIndex = -1;
	long minScore = theEntry.score;
    
	// generate high scores if prefs don't exist or contain no high scores data
	initHighScores();
    
	scoresArray = [NSMutableArray arrayWithCapacity:HIGH_SCORES_COUNT];
	textArray = [NSMutableArray arrayWithCapacity:HIGH_SCORES_COUNT];
	datesArray = [NSMutableArray arrayWithCapacity:HIGH_SCORES_COUNT];
    
	[scoresArray setArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"high scores scores"]];
	[textArray setArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"high scores text"]];
	[datesArray setArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"high scores dates"]];
    
	// find the lowest value
	for (j=0; j<HIGH_SCORES_COUNT; j++) {
		if ([[scoresArray objectAtIndex:j] longValue] < minScore) {
			minScore = [[scoresArray objectAtIndex:j] longValue];
			minIndex = j;
		}
	}

    if (theEntry.score > 0) {
        [[GameCenterManager sharedInstance] reportScore:theEntry.score forCategory:kBrogueHighScoreLeaderBoard];
        
        // attempt to rate the app
        if (theEntry.score > kRateScore && ![[iRate sharedInstance] declinedThisVersion] && ![[iRate sharedInstance] ratedThisVersion]) {
            [[iRate sharedInstance] promptIfNetworkAvailable];
        }
    }
    
	if (minIndex == -1) { // didn't qualify
		return false;
	}
    
	// minIndex identifies the score entry to be replaced
	newScore = [NSNumber numberWithLong:theEntry.score];
	newText = [NSString stringWithCString:theEntry.description encoding:NSASCIIStringEncoding];
	[scoresArray replaceObjectAtIndex:minIndex withObject:newScore];
	[textArray replaceObjectAtIndex:minIndex withObject:newText];
	[datesArray replaceObjectAtIndex:minIndex withObject:[NSDate date]];
    
	[[NSUserDefaults standardUserDefaults] setObject:scoresArray forKey:@"high scores scores"];
	[[NSUserDefaults standardUserDefaults] setObject:textArray forKey:@"high scores text"];
	[[NSUserDefaults standardUserDefaults] setObject:datesArray forKey:@"high scores dates"];
	[[NSUserDefaults standardUserDefaults] synchronize];
    
	return true;
}

void initializeLaunchArguments(enum NGCommands *command, char *path, unsigned long *seed) {
	//*command = NG_SCUM;
    *command = NG_NOTHING;
	path[0] = '\0';
	*seed = 0;
}

void migrateFilesFromLegacyStorageLocation() {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSError *err;
    
    NSString *legacyPath = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) objectAtIndex: 0];
    
    // Use a folder under Application Support named after the application.
    NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleName"];
    NSString *legacySupportPath = [legacyPath stringByAppendingPathComponent: appName];
    
    // Look up the full path to the user's Application Support folder (usually ~/Library/Application Support/).
    NSString *basePath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex: 0];
    NSString *documentsPath = basePath;//[basePath stringByAppendingPathComponent:@"/"];
    
    if ([manager fileExistsAtPath:legacySupportPath]) {
        // copy all files into the documents directory
    //    [manager copyItemAtPath:legacySupportPath toPath:documentsPath error:&err];
        
        NSArray *legacyFolderContents = [manager contentsOfDirectoryAtPath:legacySupportPath error:&err];
        
        for (NSString *source in legacyFolderContents) {
            if (![manager copyItemAtPath:[legacySupportPath stringByAppendingPathComponent:source] toPath:[documentsPath stringByAppendingPathComponent:source] error:&err]) {
                NSLog(@"%@", err);
            }
        }
    }
}

void initializeBrogueSaveLocation() {
    migrateFilesFromLegacyStorageLocation();
    
    NSFileManager *manager = [NSFileManager defaultManager];
    NSError *err;
    
    // Look up the full path to the user's Application Support folder (usually ~/Library/Application Support/).
    NSString *basePath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex: 0];
    
    // Use a folder under Application Support named after the application.
  //  NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleName"];
    NSString *documentsPath = basePath;//[basePath stringByAppendingPathComponent: appName];
    
    // Create our folder the first time it is needed.
    if (![manager fileExistsAtPath:documentsPath]) {
        [manager createDirectoryAtPath:documentsPath withIntermediateDirectories:YES attributes:nil error:&err];
    }
    
    // Set the working directory to this path, so that savegames and recordings will be stored here.
    [manager changeCurrentDirectoryPath:documentsPath];
}

#define ADD_FAKE_PADDING_FILES 0

// Returns a malloc'ed fileEntry array, and puts the file count into *fileCount.
// Also returns a pointer to the memory that holds the file names, so that it can also
// be freed afterward.
fileEntry *listFiles(short *fileCount, char **dynamicMemoryBuffer) {
	short i, count, thisFileNameLength;
	unsigned long bufferPosition, bufferSize;
	unsigned long *offsets;
	fileEntry *fileList;
	NSArray *array;
	NSFileManager *manager = [NSFileManager defaultManager];
    NSError *err;
	NSDictionary *fileAttributes;
	NSDateFormatter *dateFormatter;
	const char *thisFileName;
    
	char tempString[500];
    
	bufferPosition = bufferSize = 0;
	*dynamicMemoryBuffer = NULL;
    
	dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"MM/dd/yy"];//                initWithDateFormat:@"%1m/%1d/%y" allowNaturalLanguage:YES];
    
	array = [manager contentsOfDirectoryAtPath:[manager currentDirectoryPath] error:&err];
	count = [array count];
    
	fileList = (fileEntry *)malloc((count + ADD_FAKE_PADDING_FILES) * sizeof(fileEntry));
	offsets = (unsigned long*)malloc((count + ADD_FAKE_PADDING_FILES) * sizeof(unsigned long));
    
	for (i=0; i < count + ADD_FAKE_PADDING_FILES; i++) {
		if (i < count) {
			thisFileName = [[array objectAtIndex:i] cStringUsingEncoding:NSASCIIStringEncoding];
			fileAttributes = [manager attributesOfItemAtPath:[array objectAtIndex:i] error:nil];
            
            NSString *aDate = [dateFormatter stringFromDate:[fileAttributes fileModificationDate]];
            
            const char *date = [aDate cStringUsingEncoding:NSASCIIStringEncoding];
            
			strcpy(fileList[i].date,
				   date);
		} else {
			// Debug feature.
			sprintf(tempString, "Fake padding file %i.broguerec", i - count + 1);
			thisFileName = &(tempString[0]);
			strcpy(fileList[i].date, "12/12/12");
		}
        
		thisFileNameLength = strlen(thisFileName);
        
		if (thisFileNameLength + bufferPosition > bufferSize) {
			bufferSize += sizeof(char) * 1024;
			*dynamicMemoryBuffer = (char *) realloc(*dynamicMemoryBuffer, bufferSize);
		}
        
		offsets[i] = bufferPosition; // Have to store these as offsets instead of pointers, as realloc could invalidate pointers.
        
		strcpy(&((*dynamicMemoryBuffer)[bufferPosition]), thisFileName);
		bufferPosition += thisFileNameLength + 1;
	}
    
	// Convert the offsets to pointers.
	for (i = 0; i < count + ADD_FAKE_PADDING_FILES; i++) {
		fileList[i].path = &((*dynamicMemoryBuffer)[offsets[i]]);
	}
    
	free(offsets);
    
	*fileCount = count + ADD_FAKE_PADDING_FILES;
	return fileList;
}
