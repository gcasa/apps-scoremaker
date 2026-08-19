/*
 * Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 *
 * This file is part of ScoreMaker.
 */

#import <AppKit/AppKit.h>
#import "ScoreMakerDocument.h"
#import "ScoreMakerDocumentController.h"
#import "ScoreView.h"

static void
Require (BOOL condition, NSString *message)
{
  if (!condition)
    {
      NSLog (@"FAIL: %@", message);
      exit (1);
    }
}

int
main (void)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  [NSApplication sharedApplication];
  NSString *scorePath = [[[NSFileManager defaultManager] currentDirectoryPath]
    stringByAppendingPathComponent:@"examples/neon-causeway.score"];
  NSString *bwv1041Path = [[[NSFileManager defaultManager] currentDirectoryPath]
    stringByAppendingPathComponent:@"examples/bach-fugue-bwv-1041.score"];

  ScoreMakerDocumentController *controller = [ScoreMakerDocumentController sharedDocumentController];
  NSString *scoreType = [controller typeFromFileExtension:@"score"];
  Require ([scoreType isEqualToString:@"MusicKit Scorefile"], @"score extension did not map to scorefile type");
  Require ([controller documentClassForType:scoreType] == [ScoreMakerDocument class],
           @"scorefile type did not map to ScoreMakerDocument");

  ScoreMakerDocument *document = [[[ScoreMakerDocument alloc] init] autorelease];
  Require ([document readFromFile:scorePath ofType:scoreType], @"legacy readFromFile:ofType: failed");
  Require ([[[document scoreDocument] notes] count] > 0, @"legacy read path loaded no notes");

  NSError *openError = nil;
  NSDocument *opened = [controller openDocumentWithContentsOfURL:[NSURL fileURLWithPath:scorePath]
                                                        display:NO
                                                          error:&openError];
  Require ([opened isKindOfClass:[ScoreMakerDocument class]], @"document controller did not open scorefile");
  Require ([[[(ScoreMakerDocument *)opened scoreDocument] notes] count] > 0,
           @"document controller open loaded no notes");

  ScoreMakerDocument *bwv1041 = [[[ScoreMakerDocument alloc] init] autorelease];
  Require ([bwv1041 readFromFile:bwv1041Path ofType:scoreType], @"BWV 1041 read failed");
  Require ([[[bwv1041 scoreDocument] notes] count] > 0, @"BWV 1041 loaded no notes");

  ScoreView *view = [[[ScoreView alloc] initWithFrame:NSMakeRect (0, 0, 980, 1222)] autorelease];
  [view setDocument:[bwv1041 scoreDocument]];
  Require ([view pageCount] > 0, @"BWV 1041 layout produced no pages");

  NSError *bwv1041OpenError = nil;
  NSDocument *bwv1041Opened =
    [controller openDocumentWithContentsOfURL:[NSURL fileURLWithPath:bwv1041Path]
                                      display:YES
                                        error:&bwv1041OpenError];
  Require ([bwv1041Opened isKindOfClass:[ScoreMakerDocument class]],
           @"document controller did not display-open BWV 1041");

  NSLog (@"PASS: document open compatibility");
  [pool drain];
  return 0;
}
