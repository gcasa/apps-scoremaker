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
#import "MidiParser.h"
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

static float
AudioPeakAtPath (NSString *path, NSError **error)
{
  AVAudioFile *file = [[[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:path]
                                                     error:error] autorelease];
  if (!file)
    return 0.0f;
  AVAudioPCMBuffer *buffer = [[[AVAudioPCMBuffer alloc]
    initWithPCMFormat:[file processingFormat]
        frameCapacity:(AVAudioFrameCount)[file length]] autorelease];
  if (![file readIntoBuffer:buffer error:error])
    return 0.0f;
  float peak = 0.0f;
  for (NSUInteger channel = 0; channel < [[file processingFormat] channelCount]; channel++)
    for (AVAudioFrameCount frame = 0; frame < [buffer frameLength]; frame++)
      peak = MAX (peak, fabsf ([buffer floatChannelData][channel][frame]));
  return peak;
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
  NSString *insSource = @".Patch Names\n[Preset A]\n0=Warm Piano\n1=Wide Piano\n"
                         @"[Preset B]\n0=Analog Brass\n127=Noise Hit\n"
                         @".Instrument Definitions\n[Test Synth]\nPatch[0]=Preset A\n"
                         @"Patch[129]=Preset B\nBankSelMethod=0\n";
  NSError *insError = nil;
  NSArray *insDefinitions = [MidiParser instrumentDefinitionsFromINSString:insSource
                                                                      error:&insError];
  Require ([insDefinitions count] == 1, @".ins parser did not find the instrument definition");
  NSDictionary *insInstrument = [insDefinitions objectAtIndex:0];
  Require ([[insInstrument objectForKey:@"name"] isEqualToString:@"Test Synth"],
           @".ins instrument name was not preserved");
  NSArray *insBanks = [insInstrument objectForKey:@"banks"];
  Require ([insBanks count] == 2
             && [[[[insBanks objectAtIndex:1] objectForKey:@"patches"] objectAtIndex:127]
                   isEqualToString:@"Noise Hit"],
           @".ins banks or sparse patch names were not parsed");
  NSString *patchOnlyINS = @".Patch Names\n[Legacy Module]\n10=Bell Pad\n";
  Require ([[MidiParser instrumentDefinitionsFromINSString:patchOnlyINS error:&insError] count] == 1,
           @"patch-only .ins file did not produce an importable profile");
  NSError *sourceError = nil;
  NSString *editableSource = @"/* retained editor comment */\n"
                              @"info tempo:96 timeSignature:3/4;\n"
                              @"part Editor_Part;\nBEGIN;\nt 0;\n"
                              @"Editor_Part (1) keyNum:cs4k;\nEND;\n";
  NSArray *sourceRanges = nil;
  ScoreDocument *sourceDocument = [ScorefileParser parseString:editableSource
                                                suggestedTitle:@"Editor Test"
                                              noteSourceRanges:&sourceRanges
                                                         error:&sourceError];
  Require (sourceDocument != nil,
           [NSString stringWithFormat:@"could not parse editor source: %@", sourceError]);
  ScoreNote *sourceNote = [[sourceDocument notes] count]
                            ? [[sourceDocument notes] objectAtIndex:0] : nil;
  Require ([[sourceDocument notes] count] == 1 && [sourceNote pitch] == 61,
           [NSString stringWithFormat:@"in-memory editor source produced %lu notes at pitch %ld",
                                      (unsigned long)[[sourceDocument notes] count],
                                      (long)[sourceNote pitch]]);
  Require ([sourceRanges count] == 1, @"source parser did not produce one note range");
  NSRange editorNoteRange = [[[sourceRanges objectAtIndex:0] objectForKey:@"range"] rangeValue];
  NSString *rangedStatement = [editableSource substringWithRange:editorNoteRange];
  Require ([rangedStatement rangeOfString:@"Editor_Part (1) keyNum:cs4k;"].location
             != NSNotFound,
           @"source parser returned an incorrect note character range");
  NSString *endSubstringSource = @"part Defender_of_the_Crown;\n"
                                  @"Defender_of_the_Crown program:68;\n"
                                  @"BEGIN;\nt 0;\n"
                                  @"Defender_of_the_Crown (1) keyNum:f4k;\nEND;\n";
  NSArray *endSubstringRanges = nil;
  ScoreDocument *endSubstringDocument =
    [ScorefileParser parseString:endSubstringSource
                  suggestedTitle:@"END Substring"
                 noteSourceRanges:&endSubstringRanges
                           error:&sourceError];
  Require ([[endSubstringDocument notes] count] == 1 && [endSubstringRanges count] == 1,
           @"a part name containing END prevented source-note range mapping");
  Require ([ScorefileParser parseString:@"" suggestedTitle:@"Empty" error:&sourceError] == nil,
           @"empty editor source should fail validation");
  NSString *badTimeSource = @"part P;\nBEGIN;\nt one+;\nP (1) keyNum:c4k;\nEND;\n";
  sourceError = nil;
  Require ([ScorefileParser parseString:badTimeSource suggestedTitle:@"Bad Time"
                                  error:&sourceError] == nil,
           @"invalid time expression should fail source validation");
  Require ([[sourceError userInfo] objectForKey:ScorefileErrorRangeKey] != nil &&
             [[[sourceError userInfo] objectForKey:ScorefileErrorLineKey] unsignedIntegerValue] == 3,
           @"syntax error did not report its source range and line");
  NSRange badTimeRange = [[[sourceError userInfo] objectForKey:ScorefileErrorRangeKey] rangeValue];
  Require ([[badTimeSource substringWithRange:badTimeRange] rangeOfString:@"t one+;"].location
             != NSNotFound,
           @"invalid time expression highlighted the wrong statement");
  sourceError = nil;
  Require ([ScorefileParser parseString:@"string scoreTitle = \"broken;"
                         suggestedTitle:@"Bad Quote" error:&sourceError] == nil &&
             [[sourceError userInfo] objectForKey:ScorefileErrorRangeKey] != nil,
           @"unterminated string did not produce a ranged syntax error");

  NSString *frequencySource = @"part Detuned;\nBEGIN;\nt 0;\n"
                               @"Detuned (1) freq:330.59;\nEND;\n";
  ScoreDocument *frequencyDocument = [ScorefileParser parseString:frequencySource
                                                    suggestedTitle:@"Detuned"
                                                             error:&sourceError];
  ScoreNote *frequencyNote = [[frequencyDocument notes] objectAtIndex:0];
  Require (fabs ([frequencyNote playbackFrequency] - 330.59) < 0.000001
             && [frequencyNote pitch] == 64,
           @"scorefile frequency was not preserved alongside its notated MIDI pitch");
  NSData *frequencyScoreData = [ScorefileParser dataForDocument:frequencyDocument
                                                          error:&sourceError];
  NSString *frequencyRoundTrip = [[[NSString alloc] initWithData:frequencyScoreData
                                                        encoding:NSUTF8StringEncoding] autorelease];
  Require ([frequencyRoundTrip rangeOfString:@"freq:330.59"].location != NSNotFound,
           @"generated scorefile discarded an exact playback frequency");
  NSData *frequencyMIDI = [MidiParser dataForDocument:frequencyDocument error:&sourceError];
  const unsigned char *frequencyBytes = [frequencyMIDI bytes];
  BOOL foundPitchBend = NO;
  for (NSUInteger i = 0; i < [frequencyMIDI length]; i++)
    if ((frequencyBytes[i] & 0xf0) == 0xe0)
      { foundPitchBend = YES; break; }
  Require (foundPitchBend, @"MIDI playback did not encode tuning for an exact frequency");

  ScoreDocument *highResolution = [[[ScoreDocument alloc] init] autorelease];
  [highResolution setTicksPerQuarter:960];
  ScoreNote *highResolutionNote = [[[ScoreNote alloc] init] autorelease];
  [highResolutionNote setPitch:67];
  [highResolutionNote setTrack:2];
  [highResolutionNote setVoice:3];
  [highResolutionNote setStartTick:320];
  [highResolutionNote setDurationTicks:160];
  [[highResolution notes] addObject:highResolutionNote];
  [highResolution setTotalTicks:480];
  NSData *highResolutionData = [ScorefileParser dataForDocument:highResolution error:&sourceError];
  NSString *highResolutionSource = [[[NSString alloc]
    initWithData:highResolutionData encoding:NSUTF8StringEncoding] autorelease];
  ScoreDocument *normalized = [ScorefileParser parseString:highResolutionSource
                                            suggestedTitle:@"Normalized MIDI"
                                                     error:&sourceError];
  ScoreNote *normalizedNote = [[normalized notes] objectAtIndex:0];
  Require ([normalizedNote track] == 2 && [normalizedNote voice] == 3,
           @"generated source did not restore the original MIDI track and voice");
  Require (llround ((double)[highResolutionNote startTick] * 1000000.0 /
                    (double)[highResolution ticksPerQuarter]) ==
             llround ((double)[normalizedNote startTick] * 1000000.0 /
                    (double)[normalized ticksPerQuarter]) &&
             llround ((double)[highResolutionNote durationTicks] * 1000000.0 /
                    (double)[highResolution ticksPerQuarter]) ==
             llround ((double)[normalizedNote durationTicks] * 1000000.0 /
                    (double)[normalized ticksPerQuarter]),
           @"generated source changed high-resolution MIDI note timing");
  ScoreMeasure *highResolutionMeasure = [[highResolution measures] objectAtIndex:0];
  ScoreMeasure *normalizedMeasure = [[normalized measures] objectAtIndex:0];
  Require (llround ((double)[highResolutionMeasure durationTicks] * 1000000.0 /
                    (double)[highResolution ticksPerQuarter]) ==
             llround ((double)[normalizedMeasure durationTicks] * 1000000.0 /
                    (double)[normalized ticksPerQuarter]),
           @"generated source changed high-resolution measure timing");

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

  NSError *bachError = nil;
  ScoreDocument *bach =
    [ScorefileParser parseFileAtPath:@"examples/bach-fugue-bwv-1041.score"
                               error:&bachError];
  NSMutableSet *bachVelocities = [NSMutableSet set];
  for (ScoreNote *note in [bach notes])
    [bachVelocities addObject:[NSNumber numberWithUnsignedInteger:[note velocity]]];
  Require (bach != nil && [bachVelocities count] > 50,
           @"BWV 1041 lost its note-by-note amplitude settings");

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
  NSDictionary *savedPatch = @{ @"waveform" : @"Saw",
                                @"attack" : @0.03,
                                @"decay" : @0.2,
                                @"sustain" : @0.65,
                                @"release" : @0.4,
                                @"lfoRate" : @5.5,
                                @"lfoDepth" : @0.25,
                                @"lfoDelay" : @0.1 };
  [[persistentInstrument parameters] setObject:savedPatch forKey:@"internalSynthPatch"];
  NSDictionary *voiceTwoPatch = @{ @"name" : @"Test Square Voice",
                                    @"category" : @"Lead",
                                    @"description" : @"A test lead with velocity filter movement.",
                                    @"waveform" : @"Square",
                                    @"attack" : @0.01,
                                    @"decay" : @0.08,
                                    @"sustain" : @0.5,
                                    @"release" : @0.2,
                                    @"lfoRate" : @6.0,
                                    @"lfoDepth" : @0.0,
                                    @"lfoDelay" : @0.0,
                                    @"filterCutoff" : @1800.0,
                                    @"filterResonance" : @0.55,
                                    @"filterAttack" : @0.02,
                                    @"filterDecay" : @0.18,
                                    @"filterSustain" : @0.35,
                                    @"filterRelease" : @0.3,
                                    @"filterEnvelopeAmount" : @36.0,
                                    @"velocityToAmplitude" : @0.8,
                                    @"velocityToFilter" : @18.0,
                                    @"effects" : @[
                                      @{ @"type" : @"lowpass", @"cutoff" : @2400.0 },
                                      @{ @"type" : @"delay", @"time" : @0.08,
                                         @"feedback" : @0.25, @"mix" : @0.15 }
                                    ] };
  [[persistentInstrument parameters]
    setObject:@{ @"1" : savedPatch, @"2" : voiceTwoPatch }
       forKey:@"internalSynthPatches"];
  NSData *projectData = [ScoreProjectSerializer dataForDocument:platform error:&platformError];
  ScoreDocument *projectRoundTrip = [ScoreProjectSerializer documentFromData:projectData
                                                                       error:&platformError];
  ScoreInstrumentDefinition *restoredInstrument =
    [[[projectRoundTrip parts] objectAtIndex:0] instrument];
  ScorePartDefinition *persistentPart = [[platform parts] objectAtIndex:0];
  [persistentPart setMidiOutputUniqueID:4242];
  [persistentPart setMidiOutputName:@"Studio MIDI Interface"];
  [persistentPart setMidiFallbackMode:@"device"];
  [persistentPart setMidiFallbackUniqueID:8484];
  [persistentPart setMidiFallbackName:@"Backup MIDI Interface"];
  [persistentPart setMuted:YES];
  [persistentPart setSoloed:YES];
  [persistentPart setGain:0.75];
  [persistentPart setPan:-0.25];
  [persistentPart setGroupName:@"Woodwinds"];
  ScorePageLayout *publication = [platform pageLayout];
  [publication setPaperWidth:595.0];
  [publication setPaperHeight:842.0];
  [publication setStaffScale:0.85];
  [publication setHeaderText:@"Rehearsal score"];
  projectData = [ScoreProjectSerializer dataForDocument:platform error:&platformError];
  projectRoundTrip = [ScoreProjectSerializer documentFromData:projectData error:&platformError];
  restoredInstrument = [[[projectRoundTrip parts] objectAtIndex:0] instrument];
  ScorePartDefinition *restoredPart = [[projectRoundTrip parts] objectAtIndex:0];
  Require ([restoredPart midiOutputUniqueID] == 4242
             && [[restoredPart midiOutputName] isEqualToString:@"Studio MIDI Interface"],
           @"native project persistence lost the per-part MIDI output assignment");
  Require ([[restoredPart midiFallbackMode] isEqualToString:@"device"]
             && [restoredPart midiFallbackUniqueID] == 8484
             && [[restoredPart midiFallbackName] isEqualToString:@"Backup MIDI Interface"],
           @"native project persistence lost the per-part MIDI fallback assignment");
  Require ([restoredPart muted] && [restoredPart soloed]
             && fabs ([restoredPart gain] - 0.75) < 0.001
             && fabs ([restoredPart pan] + 0.25) < 0.001
             && [[restoredPart groupName] isEqualToString:@"Woodwinds"],
           @"native project persistence lost professional mixer and grouping state");
  Require (fabs ([[projectRoundTrip pageLayout] paperWidth] - 595.0) < 0.001
             && fabs ([[projectRoundTrip pageLayout] paperHeight] - 842.0) < 0.001
             && fabs ([[projectRoundTrip pageLayout] staffScale] - 0.85) < 0.001
             && [[[projectRoundTrip pageLayout] headerText]
                  isEqualToString:@"Rehearsal score"],
           @"native project persistence lost publication layout settings");
  ScoreDocument *reparsed = [[[ScoreDocument alloc] init] autorelease];
  [reparsed rebuildStructuredPartsFromLegacyTracks];
  [reparsed copyMIDIRoutingAssignmentsFromDocument:projectRoundTrip];
  ScorePartDefinition *reparsedPart = [[reparsed parts] objectAtIndex:0];
  Require ([reparsedPart midiOutputUniqueID] == 4242
             && [[reparsedPart midiOutputName] isEqualToString:@"Studio MIDI Interface"]
             && [[reparsedPart midiFallbackMode] isEqualToString:@"device"]
             && [reparsedPart midiFallbackUniqueID] == 8484
             && [[reparsedPart midiFallbackName] isEqualToString:@"Backup MIDI Interface"],
           @"reparsing score source lost the routing matrix fallback assignment");
  Require (
    [[restoredInstrument backendIdentifier]
      isEqualToString:@"audio-unit:1635085685:1935764848:1634758764"]
      && [[[restoredInstrument parameters] objectForKey:@"stateData"] isEqualToData:pluginState],
    @"native project persistence lost Audio Unit identity or opaque state");
  Require ([[[restoredInstrument parameters] objectForKey:@"internalSynthPatch"]
             isEqualToDictionary:savedPatch],
           @"native project persistence lost the internal synthesizer patch");
  NSDictionary *restoredVoiceTwo = [[[restoredInstrument parameters]
    objectForKey:@"internalSynthPatches"] objectForKey:@"2"];
  Require ([[restoredVoiceTwo objectForKey:@"name"] isEqualToString:@"Test Square Voice"]
             && [[restoredVoiceTwo objectForKey:@"category"] isEqualToString:@"Lead"]
             && [[restoredVoiceTwo objectForKey:@"description"] length] > 0
             && [[restoredVoiceTwo objectForKey:@"waveform"] isEqualToString:@"Square"]
             && [[restoredVoiceTwo objectForKey:@"effects"] count] == 2,
           @"native project persistence lost a voice-specific synthesizer patch");
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
  NSDictionary *factoryPatches = [ScoreRealtimeDSP factoryInternalSynthPatches];
  Require ([factoryPatches count] == 24,
           @"factory synthesizer library does not contain the expected 24 patches");
  for (NSString *factoryName in factoryPatches)
    {
      NSDictionary *factoryPatch = [factoryPatches objectForKey:factoryName];
      Require ([[factoryPatch objectForKey:@"category"] length] > 0
                 && [[factoryPatch objectForKey:@"description"] length] > 0
                 && [offlineDSP configureInternalSynthPatch:factoryPatch forVoice:1
                                                      error:&platformError],
               [NSString stringWithFormat:@"invalid factory patch: %@", factoryName]);
    }
  Require ([offlineDSP configureInternalSynthPatch:savedPatch error:&platformError]
             && [[[[offlineDSP internalSynthPatch] objectForKey:@"waveform"] description]
                   isEqualToString:@"Saw"],
           @"internal oscillator, envelope, or LFO patch configuration failed");
  Require ([offlineDSP configureInternalSynthPatch:voiceTwoPatch forVoice:2 error:&platformError]
             && [[[[offlineDSP internalSynthPatchForVoice:2] objectForKey:@"waveform"] description]
                   isEqualToString:@"Square"]
             && [[offlineDSP internalSynthEffectsForVoice:2] count] == 2,
           @"voice-specific internal synthesizer patch configuration failed");
  Require ([[[offlineDSP internalSynthPatchForVoice:2] objectForKey:@"filterEnvelopeAmount"]
              floatValue] == 36.0f
             && [[[offlineDSP internalSynthPatchForVoice:2] objectForKey:@"velocityToFilter"]
                   floatValue] == 18.0f,
           @"independent filter envelope or velocity modulation configuration failed");
  NSArray *effects = @[
    @{ @"type" : @"gain", @"decibels" : @-3.0 },
    @{ @"type" : @"lowpass", @"cutoff" : @8000.0 },
    @{ @"type" : @"compressor", @"threshold" : @-12.0, @"ratio" : @4.0 },
    @{ @"type" : @"delay", @"time" : @0.08, @"feedback" : @0.25, @"mix" : @0.15 },
    @{ @"type" : @"reverb", @"roomSize" : @0.2, @"mix" : @0.1 }
  ];
  Require ([offlineDSP configureEffects:effects error:&platformError]
             && [[offlineDSP effectConfiguration] count] == 5,
           @"real-time DSP effect chain configuration failed");
  NSString *renderPath =
    [NSTemporaryDirectory () stringByAppendingPathComponent:@"scoremaker-offline-render.caf"];
  NSArray *voiceEvents = @[
    @{ @"time" : @0.0, @"pitch" : @60, @"voice" : @1, @"velocity" : @100, @"on" : @YES },
    @{ @"time" : @0.0, @"pitch" : @67, @"voice" : @2, @"velocity" : @100, @"on" : @YES },
    @{ @"time" : @0.05, @"pitch" : @60, @"voice" : @1, @"velocity" : @0, @"on" : @NO },
    @{ @"time" : @0.05, @"pitch" : @67, @"voice" : @2, @"velocity" : @0, @"on" : @NO }
  ];
  Require ([offlineDSP renderEvents:voiceEvents
                           duration:0.12
                              toURL:[NSURL fileURLWithPath:renderPath]
                              error:&platformError],
           [NSString stringWithFormat:@"offline rendering failed: %@", platformError]);
  NSDictionary *renderAttributes =
    [[NSFileManager defaultManager] attributesOfItemAtPath:renderPath error:&platformError];
  Require ([[renderAttributes objectForKey:NSFileSize] unsignedLongLongValue] > 1024,
           @"effect-enabled offline rendering produced an empty audio file");
  float effectedPeak = AudioPeakAtPath (renderPath, &platformError);
  NSString *quietRenderPath =
    [NSTemporaryDirectory () stringByAppendingPathComponent:@"scoremaker-gain-effect.caf"];
  Require ([offlineDSP configureEffects:@[ @{ @"type" : @"gain", @"decibels" : @-24.0 } ]
                                    error:&platformError]
             && [offlineDSP renderPitches:[NSArray arrayWithObjects:@60, @64, @67, nil]
                                  duration:0.05
                                     toURL:[NSURL fileURLWithPath:quietRenderPath]
                                     error:&platformError],
           @"gain effect render failed");
  float quietPeak = AudioPeakAtPath (quietRenderPath, &platformError);
  Require (effectedPeak > 0.01f && quietPeak < effectedPeak * 0.25f,
           @"configured DSP effects did not change rendered audio");
  [[NSFileManager defaultManager] removeItemAtPath:quietRenderPath error:NULL];
  [offlineDSP configureEffects:effects error:NULL];
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
          [note setLyric:@"Glo-"];
          [note setOrnament:@"trill-mark"];
          [note setGrace:YES];
          [note setCue:YES];
          [note setTremoloStrokes:2];
          [note setHairpinStart:@"crescendo"];
          [note setPedalStart:YES];
          [note setOctaveShiftStart:1];
          [note setDirectionText:@"dolce"];
          [note setStaffAssignment:2];
        }
      else
        {
          [note setTieEnd:YES];
          [note setHairpinEnd:YES];
          [note setPedalEnd:YES];
          [note setOctaveShiftEnd:YES];
        }
      [[voices notes] addObject:note];
    }
  [pickup setKeySignatureFifths:2];
  [pickup setKeyMode:@"minor"];
  [pickup setRepeatStart:YES];
  [pickup setRehearsalMark:@"A"];
  [pickup setEndingText:@"1."];
  [measure setSystemBreak:YES];
  [measure setPageBreak:YES];
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
  ScoreDocument *converted = [[voices copy] autorelease];
  Require ([converted convertVoicesToPartsForTrack:0] == 2,
           @"multiple voices could not be converted to parts");
  NSMutableSet *convertedTracks = [NSMutableSet set];
  for (ScoreNote *note in [converted notes])
    {
      [convertedTracks addObject:[NSNumber numberWithInteger:[note track]]];
      Require ([note voice] == 1, @"voice-to-part conversion did not normalize voices");
    }
  Require ([convertedTracks count] == 2 && [[converted parts] count] == 2,
           @"voice-to-part conversion did not create independent structured parts");
  Require ([converted convertPartsToVoices] == 2,
           @"multiple parts could not be converted back to voices");
  NSMutableSet *restoredVoices = [NSMutableSet set];
  for (ScoreNote *note in [converted notes])
    {
      Require ([note track] == 0, @"part-to-voice conversion did not merge tracks");
      [restoredVoices addObject:[NSNumber numberWithInteger:[note voice]]];
    }
  Require ([restoredVoices count] == 2 && [[converted parts] count] == 1,
           @"part-to-voice conversion did not preserve independent voices");

  ScoreDocument *manyParts = [[[ScoreDocument alloc] init] autorelease];
  [manyParts setName:@"Empty placeholder" forTrack:0];
  [manyParts setProgram:@0 forTrack:0];
  for (NSInteger track = 1; track <= 8; track++)
    {
      [manyParts setName:[NSString stringWithFormat:@"Part %ld", (long)track]
                forTrack:track];
      ScoreNote *partNote = [[[ScoreNote alloc] init] autorelease];
      [partNote setTrack:track];
      [partNote setPitch:59 + track];
      [partNote setStartTick:0];
      [partNote setDurationTicks:480];
      [[manyParts notes] addObject:partNote];
    }
  Require ([manyParts convertPartsToVoices] == 8,
           @"eight populated parts were not converted to eight voices");
  NSMutableIndexSet *manyVoiceNumbers = [NSMutableIndexSet indexSet];
  for (ScoreNote *partNote in [manyParts notes])
    [manyVoiceNumbers addIndex:(NSUInteger)[partNote voice]];
  Require ([manyVoiceNumbers count] == 8 && [manyVoiceNumbers firstIndex] == 1
             && [manyVoiceNumbers lastIndex] == 8,
           @"an empty part consumed voice 1 during many-part conversion");
  Require ([[voiceRoundTrip measures][0] keySignatureFifths] == 2 &&
             [[[voiceRoundTrip measures][0] keyMode] isEqualToString:@"minor"] &&
             [[voiceRoundTrip measures][0] repeatStart] && [[voiceRoundTrip measures][1] repeatEnd],
           @"scorefile signatures or repeats did not round trip");
  ScoreNote *scoreFeatureNote = [[voiceRoundTrip notes] objectAtIndex:0];
  Require ([scoreFeatureNote tieStart] && [scoreFeatureNote tupletActual] == 3 &&
             [[scoreFeatureNote dynamic] isEqualToString:@"mf"] &&
             [[scoreFeatureNote articulation] isEqualToString:@"staccato"] &&
             [[scoreFeatureNote lyric] isEqualToString:@"Glo-"] &&
             [[scoreFeatureNote ornament] isEqualToString:@"trill-mark"] &&
             [scoreFeatureNote isGrace] && [scoreFeatureNote isCue] &&
             [scoreFeatureNote tremoloStrokes] == 2 &&
             [[scoreFeatureNote hairpinStart] isEqualToString:@"crescendo"] &&
             [scoreFeatureNote pedalStart] && [scoreFeatureNote octaveShiftStart] == 1 &&
             [[scoreFeatureNote directionText] isEqualToString:@"dolce"] &&
             [scoreFeatureNote staffAssignment] == 2 &&
             [secondVoiceNote hairpinEnd] && [secondVoiceNote pedalEnd]
             && [secondVoiceNote octaveShiftEnd] &&
             [[[voiceRoundTrip measures][0] rehearsalMark] isEqualToString:@"A"] &&
             [[[voiceRoundTrip measures][0] endingText] isEqualToString:@"1."],
           @"scorefile note notation did not round trip");
  Require ([[voiceRoundTrip measures][1] systemBreak] && [[voiceRoundTrip measures][1] pageBreak],
           @"scorefile manual layout breaks did not round trip");
  ScoreEngravingLayout *forcedLayout = [[[ScoreEngraver alloc] init]
    layoutDocument:voiceRoundTrip musicWidth:2000.0 minimumMeasureWidth:60.0];
  Require ([[forcedLayout systems] count] == 2,
           @"manual system/page break was not honored by engraving layout");
  Require ([[forcedLayout systems][1] startsNewPage],
           @"engraving layout did not preserve the forced page boundary");
  Require (ScorePageIndexForSystem ([forcedLayout systems], 1, 8) == 1
             && ScorePositionOnPageForSystem ([forcedLayout systems], 1, 8) == 0,
           @"forced page break did not advance the system to the top of the next page");

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
  Require ([[firstXMLNote lyric] isEqualToString:@"Glo-"]
             && [[firstXMLNote ornament] isEqualToString:@"trill-mark"]
             && [firstXMLNote isGrace] && [firstXMLNote isCue]
             && [firstXMLNote tremoloStrokes] == 2
             && [[firstXMLNote hairpinStart] isEqualToString:@"crescendo"]
             && [firstXMLNote pedalStart] && [firstXMLNote octaveShiftStart] == 1
             && [[firstXMLNote directionText] isEqualToString:@"dolce"]
             && [firstXMLNote staffAssignment] == 2
             && [secondXMLNote hairpinEnd] && [secondXMLNote pedalEnd]
             && [secondXMLNote octaveShiftEnd],
           @"MusicXML extended notation did not round trip");
  Require ([[xmlRoundTrip measures][0] keySignatureFifths] == 2 &&
             [[[xmlRoundTrip measures][0] keyMode] isEqualToString:@"minor"] &&
             [[xmlRoundTrip measures][0] repeatStart] && [[xmlRoundTrip measures][1] repeatEnd] &&
             [[[xmlRoundTrip measures][0] rehearsalMark] isEqualToString:@"A"] &&
             [[[xmlRoundTrip measures][0] endingText] isEqualToString:@"1."],
           @"MusicXML signatures or repeats did not round trip");
  Require ([[xmlRoundTrip measures][1] systemBreak] && [[xmlRoundTrip measures][1] pageBreak],
           @"MusicXML manual layout breaks did not round trip");

  NSData *midiKeys = [MidiParser dataForDocument:voices error:&error];
  NSString *midiKeyPath = [NSTemporaryDirectory () stringByAppendingPathComponent:@"scoremaker-keys.mid"];
  Require ([midiKeys writeToFile:midiKeyPath atomically:YES], @"could not write MIDI key test");
  ScoreDocument *midiKeyRoundTrip = [MidiParser parseFileAtPath:midiKeyPath error:&error];
  Require ([[midiKeyRoundTrip measures][0] keySignatureFifths] == 2 &&
             [[[midiKeyRoundTrip measures][0] keyMode] isEqualToString:@"minor"] &&
             [[midiKeyRoundTrip measures] count] >= 2 &&
             [[midiKeyRoundTrip measures][1] startTick] == 480 &&
             [[midiKeyRoundTrip measures][1] keySignatureFifths] == -3 &&
             [[[midiKeyRoundTrip measures][1] keyMode] isEqualToString:@"major"],
           @"MIDI key signature or mode did not round trip");

  ScoreDocument *accidentalScore = [[[ScoreDocument alloc] init] autorelease];
  [accidentalScore setTotalTicks:3840];
  [accidentalScore buildDefaultMeasures];
  for (ScoreMeasure *keyMeasure in [accidentalScore measures])
    [keyMeasure setKeySignatureFifths:1];
  NSInteger pitches[] = { 66, 65, 65, 66, 66 };
  NSInteger spellings[] = { 1, 0, 0, 1, 1 };
  NSUInteger starts[] = { 0, 480, 960, 1440, 1920 };
  NSMutableArray *accidentalNotes = [NSMutableArray array];
  for (NSUInteger i = 0; i < 5; i++)
    {
      ScoreNote *keyNote = [[[ScoreNote alloc] init] autorelease];
      [keyNote setPitch:pitches[i]];
      [keyNote setAccidental:spellings[i]];
      [keyNote setStartTick:starts[i]];
      [keyNote setDurationTicks:240];
      [[accidentalScore notes] addObject:keyNote];
      [accidentalNotes addObject:keyNote];
    }
  Require (ScoreDisplayedAccidentalForNote ([accidentalNotes objectAtIndex:0], accidentalScore)
             == NSIntegerMax &&
             ScoreDisplayedAccidentalForNote ([accidentalNotes objectAtIndex:1], accidentalScore) == 0 &&
             ScoreDisplayedAccidentalForNote ([accidentalNotes objectAtIndex:2], accidentalScore)
               == NSIntegerMax &&
             ScoreDisplayedAccidentalForNote ([accidentalNotes objectAtIndex:3], accidentalScore) == 1 &&
             ScoreDisplayedAccidentalForNote ([accidentalNotes objectAtIndex:4], accidentalScore)
               == NSIntegerMax,
           @"key-aware accidental carry or measure reset is incorrect");
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

  /* Exercise boundary behavior and failure paths that are easy to miss in file round trips. */
  ScoreDocument *timedScore = [[[ScoreDocument alloc] init] autorelease];
  [timedScore setTicksPerQuarter:480];
  [timedScore setTempoMicrosecondsPerQuarter:500000];
  [timedScore setTotalTicks:1920];
  ScoreTempoEvent *tempoChange = [[[ScoreTempoEvent alloc] init] autorelease];
  [tempoChange setTick:480];
  [tempoChange setMicrosecondsPerQuarter:1000000];
  [[timedScore tempoEvents] addObject:tempoChange];
  ScoreScheduler *timedScheduler = [[[ScoreScheduler alloc] initWithDocument:timedScore] autorelease];
  Require (fabs ([timedScheduler timeForTick:960] - 1.5) < 0.0001 &&
             [timedScheduler tickForTime:1.5] == 960,
           @"tempo-map scheduling or inverse time conversion failed");

  ScoreMIDIRoute *route = [[[ScoreMIDIRoute alloc] init] autorelease];
  [route setSourceIdentifier:@"keyboard"];
  [route setSourceChannel:2];
  [route setDestinationPartIdentifier:@"lead"];
  [route setDestinationChannel:9];
  [route setTransposition:80];
  [route setVelocityScale:2.0];
  [route setEnabled:YES];
  [[timedScore midiRoutes] addObject:route];
  ScoreMIDIRouter *router = [[[ScoreMIDIRouter alloc] initWithDocument:timedScore] autorelease];
  NSArray *routed = [router destinationsForSource:@"keyboard" channel:2 pitch:60 velocity:90];
  Require ([routed count] == 1 && [[[routed objectAtIndex:0] objectForKey:@"pitch"] integerValue] == 127
             && [[[routed objectAtIndex:0] objectForKey:@"velocity"] unsignedIntegerValue] == 127
             && [[router destinationsForSource:@"other" channel:2 pitch:60 velocity:90] count] == 0,
           @"MIDI routing filters or value clamping failed");

  ScoreSynthesisGraph *invalidGraph = [[[ScoreSynthesisGraph alloc] init] autorelease];
  ScoreSynthesisNode *duplicateA = [[[ScoreSynthesisNode alloc] init] autorelease];
  ScoreSynthesisNode *duplicateB = [[[ScoreSynthesisNode alloc] init] autorelease];
  [duplicateA setIdentifier:@"duplicate"];
  [duplicateB setIdentifier:@"duplicate"];
  [[invalidGraph nodes] addObjectsFromArray:@[ duplicateA, duplicateB ]];
  NSError *validationError = nil;
  Require (![invalidGraph validateWithError:&validationError] && validationError != nil,
           @"synthesis graph accepted duplicate node identifiers");

  ScoreCompositionProgram *invalidProgram = [[[ScoreCompositionProgram alloc] init] autorelease];
  [invalidProgram setSource:@"pattern unfinished\nnote 60 120\n"];
  Require (![ScoreCompositionEvaluator evaluateProgram:invalidProgram
                                             inDocument:timedScore
                                                  error:&validationError]
             && [[invalidProgram diagnostics] count] > 0,
           @"composition evaluator accepted an unterminated pattern");

  NSString *advancedScore = @"var beat = max(0.25, sqrt(0.25));\n"
                             "envelope shape = [(0,0),(1,1)];\n"
                             "part lead; lead synthPatch:\"Pluck\"; BEGIN;\n"
                             "t 0; lead (noteOn 7) keyNum:60.5 amp:0.5 bearing:-0.25 bright:0.8;\n"
                             "t beat; lead (noteUpdate 7) amp:0.75;\n"
                             "t 1; lead (noteOff 7); END;";
  ScoreDocument *advanced = [ScorefileParser parseString:advancedScore
                                          suggestedTitle:@"Advanced" error:&validationError];
  Require (advanced && [[advanced notes] count] == 2,
           @"math expressions or parameter-only noteUpdate parsing failed");
  ScoreNote *advancedFirst = [[advanced notes] objectAtIndex:0];
  ScoreNote *advancedSecond = [[advanced notes] objectAtIndex:1];
  Require ([advancedFirst playbackFrequency] > 0.0 && [advancedFirst velocity] == 64 &&
           [advancedSecond velocity] == 95 &&
           fabs ([[[advancedFirst performanceParameters] objectForKey:@"bright"] doubleValue]
                 - .8) < .000001 &&
           [[advanced scorefileCompatibility] objectForKey:@"envelopes"] != nil,
           @"tuning, synthesis parameters, envelopes, or update inheritance failed");
  NSData *advancedData = [ScorefileParser dataForDocument:advanced error:&validationError];
  NSString *advancedRoundTrip = [[[NSString alloc] initWithData:advancedData
                                                       encoding:NSUTF8StringEncoding] autorelease];
  Require ([advancedRoundTrip rangeOfString:@"bearing:-0.25"].location != NSNotFound &&
           [advancedRoundTrip rangeOfString:@"envelope shape"].location != NSNotFound &&
           [[[advanced scorefileCompatibility] objectForKey:@"originalSource"]
             isEqual:advancedScore],
           @"advanced Scorefile constructs were not preserved during export");

  NSString *scriptedScore = @"part aPart; aPart synthPatch:\"Fm1i\" synthPatchCount:4;\n"
                             "envelope ampFn = [(0,1)(.1,.7)|(1,0)]; BEGIN; t 0;\n"
                             "aPart (noteUpdate) bright:.6 ampEnv:ampFn;\n"
                             "int i = 0; double level = .4;\n"
                             "while (i < 3) {\n"
                             " if (i == 1) { level = .8; } else { level = .4; }\n"
                             " aPart (.25) freq:c4 * (i + 1) amp:level bearing:45 * i - 45;\n"
                             " t + .25; i = i + 1;\n"
                             "}\nEND;";
  ScoreDocument *scripted = [ScorefileParser parseString:scriptedScore
                                          suggestedTitle:@"Scripted" error:&validationError];
  Require (scripted && [[scripted notes] count] == 3,
           [NSString stringWithFormat:@"ScoreFile control flow failed: %@", validationError]);
  Require ([[[scripted notes] objectAtIndex:0] velocity] == 51 &&
           [[[scripted notes] objectAtIndex:1] velocity] == 102 &&
           fabs ([[[[[scripted notes] objectAtIndex:2] performanceParameters]
                     objectForKey:@"bright"] doubleValue] - .6) < .000001 &&
           [[[[scripted scorefileCompatibility] objectForKey:@"envelopesObjects"]
              objectForKey:@"ampFn"] objectForKey:@"hasSustainPoint"] != nil,
           @"conditionals, part defaults, or executable envelope metadata failed");

  NSString *randomProgram = @"part Random; BEGIN; t 0; int randomSeed = 4242; int i = 0;"
                             "while (i < 4) { Random (.1) freq:220 + ran * 110 amp:.5;"
                             "t + .1; i = i + 1; } END;";
  ScoreDocument *randomFirst = [ScorefileParser parseString:randomProgram
                                             suggestedTitle:@"Random A" error:&validationError];
  ScoreDocument *randomSecond = [ScorefileParser parseString:randomProgram
                                              suggestedTitle:@"Random B" error:&validationError];
  Require (randomFirst && randomSecond && [[randomFirst notes] count] == 4 &&
           [[randomSecond notes] count] == 4,
           @"deterministic random ScoreFile did not generate its notes");
  for (NSUInteger randomIndex = 0; randomIndex < 4; randomIndex++)
    Require (fabs ([[[randomFirst notes] objectAtIndex:randomIndex] playbackFrequency] -
                   [[[randomSecond notes] objectAtIndex:randomIndex] playbackFrequency]) < 1e-12,
             @"identical ScoreFile source produced different random values");
  NSString *differentSeedProgram = [randomProgram
    stringByReplacingOccurrencesOfString:@"randomSeed = 4242"
                              withString:@"randomSeed = 4243"];
  ScoreDocument *randomDifferent = [ScorefileParser parseString:differentSeedProgram
                                                 suggestedTitle:@"Random C"
                                                          error:&validationError];
  Require (fabs ([[[randomFirst notes] objectAtIndex:0] playbackFrequency] -
                 [[[randomDifferent notes] objectAtIndex:0] playbackFrequency]) > 1e-9,
           @"an explicit randomSeed did not change the generated sequence");

  NSString *implicitRandom = @"part Random; BEGIN; t 0; Random (.1) freq:220 + ran * 10; END;";
  ScoreDocument *implicitFirst = [ScorefileParser parseString:implicitRandom
                                               suggestedTitle:@"Implicit A"
                                                        error:&validationError];
  ScoreDocument *implicitSecond = [ScorefileParser parseString:
    [@"/* comments do not perturb the musical seed */\n" stringByAppendingString:implicitRandom]
                                                suggestedTitle:@"Implicit B"
                                                         error:&validationError];
  Require (fabs ([[[implicitFirst notes] objectAtIndex:0] playbackFrequency] -
                 [[[implicitSecond notes] objectAtIndex:0] playbackFrequency]) < 1e-12,
           @"comments unexpectedly changed the default deterministic random seed");

  NSString *includeDirectory = [NSTemporaryDirectory () stringByAppendingPathComponent:
    [NSString stringWithFormat:@"scoremaker-includes-%@", [[NSUUID UUID] UUIDString]]];
  Require ([[NSFileManager defaultManager] createDirectoryAtPath:includeDirectory
                                      withIntermediateDirectories:YES attributes:nil
                                                           error:&validationError],
           @"could not create include compatibility fixture");
  NSString *includeRoot = [includeDirectory stringByAppendingPathComponent:@"root.score"];
  NSString *includeChild = [includeDirectory stringByAppendingPathComponent:@"child.score"];
  NSString *includeRootSource = @"part Included; BEGIN;\ninclude \"child.score\";\n"
                                 "t 1; Included (.5) keyNum:e4k; END;";
  NSString *includeChildSource = @"t 0; Included (.5) keyNum:c4k;";
  Require ([includeRootSource writeToFile:includeRoot atomically:YES
                                  encoding:NSUTF8StringEncoding error:&validationError] &&
           [includeChildSource writeToFile:includeChild atomically:YES
                                   encoding:NSUTF8StringEncoding error:&validationError],
           @"could not write include compatibility fixture");
  ScoreDocument *included = [ScorefileParser parseFileAtPath:includeRoot error:&validationError];
  Require (included && [[included notes] count] == 2 &&
           [[[[included notes] objectAtIndex:0] provenance]
             isEqual:[includeChild stringByStandardizingPath]] &&
           [[[[included notes] objectAtIndex:1] provenance]
             isEqual:[includeRoot stringByStandardizingPath]] &&
           [[[included scorefileCompatibility] objectForKey:@"sourceFiles"]
             containsObject:[includeChild stringByStandardizingPath]] &&
           [[[included scorefileCompatibility] objectForKey:@"sourceFiles"]
             containsObject:[includeRoot stringByStandardizingPath]],
           @"included notes did not retain canonical per-file provenance");

  NSString *cycleA = [includeDirectory stringByAppendingPathComponent:@"cycle-a.score"];
  NSString *cycleB = [includeDirectory stringByAppendingPathComponent:@"cycle-b.score"];
  [@"include \"cycle-b.score\";" writeToFile:cycleA atomically:YES
                                      encoding:NSUTF8StringEncoding error:&validationError];
  [@"include \"cycle-a.score\";" writeToFile:cycleB atomically:YES
                                      encoding:NSUTF8StringEncoding error:&validationError];
  validationError = nil;
  Require ([ScorefileParser parseFileAtPath:cycleA error:&validationError] == nil &&
           [[[validationError localizedDescription] lowercaseString] rangeOfString:@"cycle"].location
             != NSNotFound,
           @"an include cycle did not produce an explicit diagnostic");

  NSMutableString *tooManyIncludes = [NSMutableString string];
  for (NSUInteger includeIndex = 0; includeIndex < 129; includeIndex++)
    [tooManyIncludes appendString:@"include \"child.score\";\n"];
  NSString *includeBudgetPath = [includeDirectory stringByAppendingPathComponent:@"too-many.score"];
  [tooManyIncludes writeToFile:includeBudgetPath atomically:YES
                       encoding:NSUTF8StringEncoding error:&validationError];
  validationError = nil;
  Require ([ScorefileParser parseFileAtPath:includeBudgetPath error:&validationError] == nil &&
           [[validationError localizedDescription] rangeOfString:@"128"].location != NSNotFound,
           @"include-count budget was not enforced");

  NSMutableString *deepScript = [NSMutableString stringWithString:@"part Deep; BEGIN; int x = 1;"];
  for (NSUInteger depth = 0; depth < 129; depth++)
    [deepScript appendString:@"if (x) {"];
  [deepScript appendString:@"Deep (.1) keyNum:c4k;"];
  for (NSUInteger depth = 0; depth < 129; depth++)
    [deepScript appendString:@"}"];
  [deepScript appendString:@"END;"];
  validationError = nil;
  Require ([ScorefileParser parseString:deepScript suggestedTitle:@"Too Deep"
                                   error:&validationError] == nil &&
           [[validationError localizedDescription] rangeOfString:@"128"].location != NSNotFound,
           @"script-nesting budget was not enforced");
  [[NSFileManager defaultManager] removeItemAtPath:includeDirectory error:NULL];

  NSString *algorithmicPath = @"examples/algorithmic-cycle-of-fifths.score";
  NSString *algorithmicSource = [NSString stringWithContentsOfFile:algorithmicPath
                                                           encoding:NSUTF8StringEncoding
                                                              error:&validationError];
  NSArray *algorithmicRanges = nil;
  ScoreDocument *algorithmic = [ScorefileParser parseString:algorithmicSource
                                             suggestedTitle:@"Algorithmic Trace"
                                           noteSourceRanges:&algorithmicRanges
                                                      error:&validationError];
  Require (algorithmic && [algorithmicRanges count] == [[algorithmic notes] count],
           @"algorithmic notes did not retain source-trace mappings");
  for (NSDictionary *mapping in algorithmicRanges)
    {
      NSRange range = [[mapping objectForKey:@"range"] rangeValue];
      NSString *origin = [algorithmicSource substringWithRange:range];
      Require ([origin rangeOfString:@"Harmony"].location != NSNotFound ||
               [origin rangeOfString:@"Sparkle"].location != NSNotFound,
               @"generated note mapped to the wrong algorithmic source statement");
    }

  Require ([MidiParser parseFileAtPath:@"/path/that/does/not/exist.mid" error:&validationError]
             == nil
             && [MusicXMLParser parseFileAtPath:@"/path/that/does/not/exist.musicxml"
                                           error:&validationError] == nil
             && [ScorefileParser parseFileAtPath:@"/path/that/does/not/exist.score"
                                            error:&validationError] == nil,
           @"file parsers did not reject missing input files");
  Require ([layout systemContainingTick:NSUIntegerMax] == [[layout systems] lastObject]
             && [layoutSystem fractionForTick:[layoutSystem endTick]] == 1.0,
           @"engraving layout boundary lookup failed");

  NSLog (@"PASS: complete application compatibility suite");
  [pool drain];
  return 0;
}
