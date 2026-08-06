/*
 * Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 *
 * This file is part of ScoreMaker.
 *
 * ScoreMaker is free software: you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 2.1 of the License, or (at
 * your option) any later version.
 *
 * ScoreMaker is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
 * License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with ScoreMaker.  If not, see <https://www.gnu.org/licenses/>.
 */

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "ScorefileParser.h"
#import "ScoreProjectSerializer.h"
#import "MusicXMLParser.h"
#import "NotationModel.h"
#import "EngravingLayout.h"
#import "MusicEngine.h"
#import "MusicPlatformModel.h"
#import "RealtimeDSP.h"

static void
Require (BOOL condition, NSString *message)
{
  if (!condition)
    {
      NSLog (@"FAIL: %@", message);
      exit (1);
    }
}

static void
CompareNotes (ScoreDocument *left, ScoreDocument *right)
{
  Require ([[left notes] count] == [[right notes] count], @"note count changed after round trip");
  for (NSUInteger index = 0; index < [[left notes] count]; index++)
    {
      ScoreNote *a = [[left notes] objectAtIndex:index];
      ScoreNote *b = [[right notes] objectAtIndex:index];
      Require ([a pitch] == [b pitch] && [a track] == [b track] && [a startTick] == [b startTick] &&
                 [a durationTicks] == [b durationTicks] && [a isRest] == [b isRest] &&
                 [a velocity] == [b velocity],
               @"legacy note data changed after round trip");
    }
}

int
main (void)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSDirectoryEnumerator *examples = [[NSFileManager defaultManager] enumeratorAtPath:@"examples"];
  for (NSString *name in examples)
    {
      if (![[name pathExtension] isEqualToString:@"score"])
        continue;
      NSError *error = nil;
      ScoreDocument *document =
        [ScorefileParser parseFileAtPath:[@"examples" stringByAppendingPathComponent:name]
                                   error:&error];
      Require (document != nil, [NSString stringWithFormat:@"could not parse %@: %@", name, error]);
      Require ([[document measures] count] > 0,
               [NSString stringWithFormat:@"%@ has no synthesized measures", name]);
      Require ([[document parts] count] > 0,
               [NSString stringWithFormat:@"%@ has no structured parts", name]);
      for (ScoreNote *note in [document notes])
        Require ([note voice] >= 1, @"example note has an invalid voice number");
      NSData *data = [ScorefileParser dataForDocument:document error:&error];
      Require (data != nil, [NSString stringWithFormat:@"could not serialize %@: %@", name, error]);
      NSString *text = [[[NSString alloc] initWithData:data
                                              encoding:NSUTF8StringEncoding] autorelease];
      Require ([text rangeOfString:@"ScoreMaker Metadata V1"].location != NSNotFound,
               @"V1 metadata was removed");
      Require ([text rangeOfString:@"ScoreMaker Structure V2"].location != NSNotFound,
               @"V2 structure metadata is missing");
      NSString *path =
        [NSTemporaryDirectory () stringByAppendingPathComponent:[name lastPathComponent]];
      Require ([data writeToFile:path atomically:YES], @"could not write temporary score");
      ScoreDocument *roundTrip = [ScorefileParser parseFileAtPath:path error:&error];
      Require (roundTrip != nil,
               [NSString stringWithFormat:@"could not reparse %@: %@", name, error]);
      CompareNotes (document, roundTrip);
      Require ([[document measures] count] == [[roundTrip measures] count],
               @"measure count changed after round trip");
    }

  ScoreDocument *platform = [[[ScoreDocument alloc] init] autorelease];
  ScoreCompositionProgram *program = [platform compositionProgram];
  [program setSource:@"part 0 Lead\nvoice 1\nnote 60 480\nnote 64 480\nrest 0 240\n"];
  NSError *platformError = nil;
  Require ([ScoreCompositionEvaluator evaluateProgram:program
                                           inDocument:platform
                                                error:&platformError],
           [NSString stringWithFormat:@"composition evaluation failed: %@", platformError]);
  Require ([[platform notes] count] == 3 && [[platform parts] count] == 1,
           @"composition evaluation did not generate a structured part");
  [program setSource:@"pattern motif\nnote 60 120\nnote 64 120\nend\n"
                     @"velocity 100\nplay motif 2 12\n"];
  Require ([ScoreCompositionEvaluator evaluateProgram:program
                                           inDocument:platform
                                                error:&platformError],
           @"pattern composition evaluation failed");
  ScoreNote *patternNote = [[platform notes] objectAtIndex:0];
  Require ([[platform notes] count] == 4 && [patternNote pitch] == 72 &&
             [patternNote velocity] == 100 &&
             [[patternNote provenance] hasPrefix:@"composition:pattern"],
           @"pattern repetition, transformation, velocity, or provenance failed");
  ScoreScheduler *scheduler = [[[ScoreScheduler alloc] initWithDocument:platform] autorelease];
  Require (fabs ([scheduler timeForTick:480] - 0.5) < 0.0001,
           @"scheduler produced an incorrect tick time");
  Require ([[scheduler eventsFromTick:0 throughTick:1200] count] == 8,
           @"scheduler did not produce note-on and note-off events");

  ScoreInstrumentDefinition *persistentInstrument =
    [[[[platform parts] objectAtIndex:0] instrument] retain];
  ScoreSynthesisNode *partOscillator = [[[ScoreSynthesisNode alloc] init] autorelease];
  [partOscillator setTypeIdentifier:@"oscillator"];
  [[[[platform parts] objectAtIndex:0] synthesisGraph].nodes addObject:partOscillator];
  [persistentInstrument setBackendIdentifier:@"audio-unit:1635085685:1935764848:1634758764"];
  NSData *pluginState = [@"opaque plugin state" dataUsingEncoding:NSUTF8StringEncoding];
  [[persistentInstrument parameters] setObject:pluginState forKey:@"stateData"];
  NSData *projectData = [ScoreProjectSerializer dataForDocument:platform error:&platformError];
  ScoreDocument *projectRoundTrip = [ScoreProjectSerializer documentFromData:projectData
                                                                       error:&platformError];
  ScoreInstrumentDefinition *restoredInstrument =
    [[[projectRoundTrip parts] objectAtIndex:0] instrument];
  Require (
    [[restoredInstrument backendIdentifier]
      isEqualToString:@"audio-unit:1635085685:1935764848:1634758764"]
      && [[[restoredInstrument parameters] objectForKey:@"stateData"] isEqualToData:pluginState],
    @"native project persistence lost Audio Unit identity or opaque state");
  NSDictionary *componentIdentity = @{
    @"type" : @1635085685,
    @"subtype" : @1935764848,
    @"manufacturerCode" : @1634758764
  };
  Require ([[ScoreRealtimeDSP identifierForAudioUnitDescription:componentIdentity]
             isEqualToString:@"61756d75-73616d70-6170706c"],
           @"Audio Unit identity is not stable enough for relinking and preset storage");
  Require ([[[[[projectRoundTrip parts] objectAtIndex:0] synthesisGraph] nodes] count] == 1,
           @"native project persistence lost a per-part synthesis graph");
  NSMutableDictionary *legacyProject =
    [[NSJSONSerialization JSONObjectWithData:projectData
                                     options:NSJSONReadingMutableContainers
                                       error:&platformError] mutableCopy];
  [legacyProject setObject:@1 forKey:@"version"];
  [legacyProject removeObjectForKey:@"scorefileLength"];
  NSData *legacyData = [NSJSONSerialization dataWithJSONObject:legacyProject
                                                       options:0
                                                         error:&platformError];
  Require ([ScoreProjectSerializer documentFromData:legacyData error:&platformError] != nil,
           @"version 1 native project migration failed");
  [legacyProject setObject:@2 forKey:@"version"];
  [legacyProject setObject:@1 forKey:@"scorefileLength"];
  NSData *damagedData = [NSJSONSerialization dataWithJSONObject:legacyProject
                                                        options:0
                                                          error:&platformError];
  Require ([ScoreProjectSerializer documentFromData:damagedData error:NULL] == nil,
           @"damaged native project data was not rejected");
  [legacyProject release];
  [persistentInstrument release];

  ScoreDocument *stressDocument = [[[ScoreDocument alloc] init] autorelease];
  [stressDocument setTotalTicks:200000];
  for (NSUInteger index = 0; index < 2000; index++)
    {
      ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
      [note setPitch:48 + index % 36];
      [note setStartTick:index * 100];
      [note setDurationTicks:80];
      [[stressDocument notes] addObject:note];
    }
  ScoreScheduler *stressScheduler =
    [[[ScoreScheduler alloc] initWithDocument:stressDocument] autorelease];
  Require ([[stressScheduler eventsFromTick:0 throughTick:200000] count] == 4000,
           @"large-score scheduler lost events under stress");

  ScoreRealtimeDSP *offlineDSP = [[[ScoreRealtimeDSP alloc] init] autorelease];
  NSString *renderPath =
    [NSTemporaryDirectory () stringByAppendingPathComponent:@"scoremaker-offline-render.caf"];
  Require ([offlineDSP renderPitches:[NSArray arrayWithObjects:@60, @64, @67, nil]
                            duration:0.05
                               toURL:[NSURL fileURLWithPath:renderPath]
                               error:&platformError],
           [NSString stringWithFormat:@"offline rendering failed: %@", platformError]);
  NSDictionary *renderAttributes =
    [[NSFileManager defaultManager] attributesOfItemAtPath:renderPath error:&platformError];
  Require ([[renderAttributes objectForKey:NSFileSize] unsignedLongLongValue] > 1024,
           @"offline rendering produced an empty audio file");
  [[NSFileManager defaultManager] removeItemAtPath:renderPath error:NULL];

  NSString *timingPath =
    [NSTemporaryDirectory () stringByAppendingPathComponent:@"scoremaker-sample-timing.caf"];
  NSArray *timedEvents = @[
    @{@"time" : @0.05,
      @"pitch" : @69,
      @"velocity" : @127,
      @"on" : @YES},
    @{@"time" : @0.10,
      @"pitch" : @69,
      @"velocity" : @0,
      @"on" : @NO}
  ];
  Require ([offlineDSP renderEvents:timedEvents
                           duration:0.15
                              toURL:[NSURL fileURLWithPath:timingPath]
                              error:&platformError],
           @"sample-timing render failed");
  AVAudioFile *timingFile = [[[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:timingPath]
                                                           error:&platformError] autorelease];
  AVAudioPCMBuffer *timingBuffer = [[[AVAudioPCMBuffer alloc]
    initWithPCMFormat:[timingFile processingFormat]
        frameCapacity:(AVAudioFrameCount)[timingFile length]] autorelease];
  Require ([timingFile readIntoBuffer:timingBuffer error:&platformError],
           @"could not inspect sample-timing render");
  float *samples = [timingBuffer floatChannelData][0];
  float preOnsetPeak = 0.0f, soundingPeak = 0.0f;
  for (NSUInteger frame = 0; frame < 2400; frame++)
    preOnsetPeak = MAX (preOnsetPeak, fabsf (samples[frame]));
  for (NSUInteger frame = 2401; frame < 4800; frame++)
    soundingPeak = MAX (soundingPeak, fabsf (samples[frame]));
  Require (preOnsetPeak == 0.0f && soundingPeak > 0.01f,
           @"offline DSP events were not applied at the requested sample frame");
  [[NSFileManager defaultManager] removeItemAtPath:timingPath error:NULL];

  ScoreSynthesisNode *oscillator = [[[ScoreSynthesisNode alloc] init] autorelease];
  [oscillator setTypeIdentifier:@"oscillator"];
  ScoreSynthesisNode *output = [[[ScoreSynthesisNode alloc] init] autorelease];
  [output setTypeIdentifier:@"output"];
  [[[platform synthesisGraph] nodes]
    addObjectsFromArray:[NSArray arrayWithObjects:oscillator, output, nil]];
  ScoreSynthesisConnection *connection = [[[ScoreSynthesisConnection alloc] init] autorelease];
  [connection setSourceNodeIdentifier:[oscillator identifier]];
  [connection setSourcePort:@"audio"];
  [connection setDestinationNodeIdentifier:[output identifier]];
  [connection setDestinationPort:@"audio"];
  [[[platform synthesisGraph] connections] addObject:connection];
  Require ([[ScoreSynthesisCompiler processingOrderForGraph:[platform synthesisGraph]
                                                      error:&platformError] count]
             == 2,
           @"synthesis graph compilation failed");

  ScoreDocument *voices = [[[ScoreDocument alloc] init] autorelease];
  [voices setTotalTicks:1440];
  ScoreMeasure *pickup = [[[ScoreMeasure alloc] init] autorelease];
  [pickup setNumber:0];
  [pickup setStartTick:0];
  [pickup setDurationTicks:480];
  [pickup setTimeSignatureNumerator:4];
  [pickup setTimeSignatureDenominator:4];
  [pickup setImplicit:YES];
  ScoreMeasure *measure = [[[ScoreMeasure alloc] init] autorelease];
  [measure setNumber:1];
  [measure setStartTick:480];
  [measure setDurationTicks:960];
  [measure setTimeSignatureNumerator:2];
  [measure setTimeSignatureDenominator:4];
  [[voices measures] addObjectsFromArray:[NSArray arrayWithObjects:pickup, measure, nil]];
  for (NSInteger voice = 1; voice <= 2; voice++)
    {
      ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
      [note setPitch:voice == 1 ? 72 : 48];
      [note setTrack:0];
      [note setChannel:0];
      [note setStartTick:480];
      [note setDurationTicks:480];
      [note setVoice:voice];
      [note setMeasureIndex:1];
      [note setVelocity:voice == 1 ? 96 : 48];
      if (voice == 1)
        {
          [note setTieStart:YES];
          [note setTupletActual:3];
          [note setTupletNormal:2];
          [note setDynamic:@"mf"];
          [note setArticulation:@"staccato"];
        }
      else
        {
          [note setTieEnd:YES];
        }
      [[voices notes] addObject:note];
    }
  [pickup setKeySignatureFifths:2];
  [pickup setRepeatStart:YES];
  [measure setKeySignatureFifths:-3];
  [measure setRepeatEnd:YES];
  NSError *error = nil;
  NSData *voiceData = [ScorefileParser dataForDocument:voices error:&error];
  NSString *voicePath =
    [NSTemporaryDirectory () stringByAppendingPathComponent:@"scoremaker-voices.score"];
  Require ([voiceData writeToFile:voicePath atomically:YES], @"could not write voice test score");
  ScoreDocument *voiceRoundTrip = [ScorefileParser parseFileAtPath:voicePath error:&error];
  Require ([[voiceRoundTrip measures] count] == 2, @"explicit measures did not round trip");
  ScoreNote *firstVoiceNote = [[voiceRoundTrip notes] objectAtIndex:0];
  ScoreNote *secondVoiceNote = [[voiceRoundTrip notes] objectAtIndex:1];
  Require ([firstVoiceNote voice] == 1 && [secondVoiceNote voice] == 2,
           @"voices did not round trip");
  Require ([firstVoiceNote velocity] == 96 && [secondVoiceNote velocity] == 48,
           @"velocities did not round trip");
  Require ([[voiceRoundTrip measures][0] keySignatureFifths] == 2 &&
             [[voiceRoundTrip measures][0] repeatStart] && [[voiceRoundTrip measures][1] repeatEnd],
           @"scorefile signatures or repeats did not round trip");
  ScoreNote *scoreFeatureNote = [[voiceRoundTrip notes] objectAtIndex:0];
  Require ([scoreFeatureNote tieStart] && [scoreFeatureNote tupletActual] == 3 &&
             [[scoreFeatureNote dynamic] isEqualToString:@"mf"] &&
             [[scoreFeatureNote articulation] isEqualToString:@"staccato"],
           @"scorefile note notation did not round trip");

  NSData *musicXML = [MusicXMLParser dataForDocument:voices error:&error];
  NSString *xmlPath =
    [NSTemporaryDirectory () stringByAppendingPathComponent:@"scoremaker-voices.musicxml"];
  Require ([musicXML writeToFile:xmlPath atomically:YES], @"could not write MusicXML voice test");
  ScoreDocument *xmlRoundTrip = [MusicXMLParser parseFileAtPath:xmlPath error:&error];
  Require ([[xmlRoundTrip measures] count] == 2, @"MusicXML measures did not round trip");
  Require ([[xmlRoundTrip notes] count] == 2, @"MusicXML notes did not round trip");
  ScoreNote *firstXMLNote = [[xmlRoundTrip notes] objectAtIndex:0];
  ScoreNote *secondXMLNote = [[xmlRoundTrip notes] objectAtIndex:1];
  Require ([firstXMLNote voice] == 1 && [secondXMLNote voice] == 2,
           @"MusicXML voices did not round trip");
  Require ([[xmlRoundTrip measures][0] keySignatureFifths] == 2 &&
             [[xmlRoundTrip measures][0] repeatStart] && [[xmlRoundTrip measures][1] repeatEnd],
           @"MusicXML signatures or repeats did not round trip");
  ScoreNote *xmlFeatureNote = [[xmlRoundTrip notes] objectAtIndex:0];
  Require ([xmlFeatureNote tieStart] && [xmlFeatureNote tupletActual] == 3 &&
             [[xmlFeatureNote dynamic] isEqualToString:@"mf"] &&
             [[xmlFeatureNote articulation] isEqualToString:@"staccato"],
           @"MusicXML note notation did not round trip");

  ScoreDocument *snapshot = [voices copy];
  ScoreNote *editedNote = [[voices notes] objectAtIndex:0];
  [editedNote setPitch:84];
  [[voices measures] removeLastObject];
  ScoreNote *snapshotNote = [[snapshot notes] objectAtIndex:0];
  Require ([snapshotNote pitch] == 72, @"undo snapshot did not deeply copy notes");
  Require ([[snapshot measures] count] == 2, @"undo snapshot did not deeply copy measures");
  [snapshot release];

  NSArray *notation = [ScoreNotationModel elementsForDocument:voices];
  NSUInteger ties = 0, tuplets = 0, dynamics = 0, keys = 0, repeats = 0;
  for (ScoreNotationElement *element in notation)
    {
      if ([element kind] == ScoreNotationTie)
        ties++;
      if ([element kind] == ScoreNotationTuplet)
        tuplets++;
      if ([element kind] == ScoreNotationDynamic)
        dynamics++;
      if ([element kind] == ScoreNotationKeySignature)
        keys++;
      if ([element kind] == ScoreNotationRepeat)
        repeats++;
    }
  Require (ties == 2 && tuplets == 1 && dynamics == 1 && keys == 1 && repeats == 1,
           @"unified notation model omitted semantic elements");
  ScoreEngraver *engraver = [[[ScoreEngraver alloc] init] autorelease];
  ScoreEngravingLayout *layout = [engraver layoutDocument:voices
                                               musicWidth:684
                                      minimumMeasureWidth:140];
  Require ([[layout systems] count] > 0 && [[layout notationElements] count] == [notation count],
           @"engraving pipeline did not retain normalized notation");
  ScoreEngravingSystem *layoutSystem = [[layout systems] objectAtIndex:0];
  Require ([layoutSystem fractionForTick:[layoutSystem startTick]] == 0.0,
           @"engraving system tick mapping is invalid");

  ScoreDocument *denseScore = [[[ScoreDocument alloc] init] autorelease];
  ScoreMeasure *denseMeasure = [[[ScoreMeasure alloc] init] autorelease];
  [denseMeasure setStartTick:0];
  [denseMeasure setDurationTicks:1920];
  [[denseScore measures] addObject:denseMeasure];
  for (NSUInteger onset = 0; onset < 6; onset++)
    for (NSUInteger chordTone = 0; chordTone < 6; chordTone++)
      {
        ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
        [note setStartTick:onset * 240];
        [note setDurationTicks:240];
        [note setPitch:60 + chordTone];
        [note setAccidental:(chordTone % 2) ? 1 : -1];
        [note setVoice:1 + chordTone % 2];
        if (onset == 0)
          {
            [note setDynamic:@"fortissimo"];
            [note setArticulation:@"accent"];
          }
        [[denseScore notes] addObject:note];
      }
  CGFloat sparseWidth = [engraver widthForMeasure:pickup document:voices minimum:40.0];
  CGFloat denseWidth = [engraver widthForMeasure:denseMeasure document:denseScore minimum:40.0];
  Require (denseWidth > sparseWidth * 2.0,
           @"collision-aware engraving did not reserve space for dense chords and annotations");

  NSLog (@"PASS: .score compatibility and V2 structure round trips");
  [pool drain];
  return 0;
}
