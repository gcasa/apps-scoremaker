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

#import "MusicXMLParser.h"
#import <math.h>

static NSString *const MusicXMLErrorDomain = @"ScoreMakerMusicXML";

static NSString *
EscapeXML (NSString *string)
{
  NSString *escaped = [string stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
  escaped = [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
  escaped = [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
  escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
  return [escaped stringByReplacingOccurrencesOfString:@"'" withString:@"&apos;"];
}

static NSInteger
PitchClassForStep (NSString *step)
{
  if ([step isEqualToString:@"C"])
    return 0;
  if ([step isEqualToString:@"D"])
    return 2;
  if ([step isEqualToString:@"E"])
    return 4;
  if ([step isEqualToString:@"F"])
    return 5;
  if ([step isEqualToString:@"G"])
    return 7;
  if ([step isEqualToString:@"A"])
    return 9;
  return 11;
}

static NSString *
StepForPitch (NSInteger pitch, NSInteger accidental)
{
  static NSString *sharpSteps[]
    = { @"C", @"C", @"D", @"D", @"E", @"F", @"F", @"G", @"G", @"A", @"A", @"B" };
  static NSString *flatSteps[]
    = { @"C", @"D", @"D", @"E", @"E", @"F", @"G", @"G", @"A", @"A", @"B", @"B" };
  NSInteger pc = pitch % 12;
  if (pc < 0)
    pc += 12;
  return accidental < 0 ? flatSteps[pc] : sharpSteps[pc];
}

@interface MusicXMLImportDelegate : NSObject <NSXMLParserDelegate>
{
  ScoreDocument *_document;
  NSMutableString *_text;
  NSMutableDictionary *_partNames;
  NSMutableDictionary *_partPrograms;
  NSMutableDictionary *_partIndexes;
  NSString *_currentPartID;
  NSInteger _currentTrack;
  double _currentQuarter;
  double _lastNoteStartQuarter;
  double _measureStartQuarter;
  double _measureMaxQuarter;
  NSUInteger _divisions;
  BOOL _measureImplicit;
  BOOL _foundTempo;
  BOOL _inNote;
  BOOL _inBackup;
  BOOL _inForward;
  BOOL _noteRest;
  BOOL _noteChord;
  BOOL _noteGrace;
  BOOL _noteCue;
  NSUInteger _noteTremoloStrokes;
  BOOL _noteSlurStart;
  BOOL _noteSlurEnd;
  BOOL _noteTieStart;
  BOOL _noteTieEnd;
  NSUInteger _noteTupletActual;
  NSUInteger _noteTupletNormal;
  NSString *_noteArticulation;
  NSString *_noteLyric;
  NSString *_noteOrnament;
  NSString *_pendingDynamic;
  NSString *_pendingHairpinStart;
  BOOL _pendingHairpinEnd;
  BOOL _pendingPedalStart;
  BOOL _pendingPedalEnd;
  NSInteger _pendingOctaveShiftStart;
  BOOL _pendingOctaveShiftEnd;
  NSString *_pendingDirectionText;
  NSInteger _currentKeyFifths;
  NSString *_currentKeyMode;
  BOOL _measureRepeatStart;
  BOOL _measureRepeatEnd;
  NSString *_measureRehearsalMark;
  NSString *_measureEndingText;
  BOOL _measureSystemBreak;
  BOOL _measurePageBreak;
  NSInteger _noteVoice;
  NSInteger _noteStaff;
  NSInteger _currentMeasureNumber;
  NSInteger _currentMeasureIndex;
  BOOL _currentMeasureNumberSpecified;
  NSString *_noteStep;
  NSInteger _noteAlter;
  NSInteger _noteOctave;
  double _noteDurationQuarters;
  NSString *_scoreTitle;
  NSString *_scoreTitleFontName;
  NSString *_scoreComposer;
  BOOL _inComposerCreator;
}

- (ScoreDocument *)document;
@end

@implementation MusicXMLImportDelegate

- (id)init
{
  self = [super init];
  if (self)
    {
      _document = [[ScoreDocument alloc] init];
      [_document setTicksPerQuarter:480];
      _text = [[NSMutableString alloc] init];
      _partNames = [[NSMutableDictionary alloc] init];
      _partPrograms = [[NSMutableDictionary alloc] init];
      _partIndexes = [[NSMutableDictionary alloc] init];
      _divisions = 1;
      _currentKeyMode = [@"major" copy];
    }
  return self;
}

- (void)dealloc
{
  [_document release];
  [_text release];
  [_partNames release];
  [_partPrograms release];
  [_partIndexes release];
  [_currentPartID release];
  [_noteStep release];
  [_noteArticulation release];
  [_noteLyric release];
  [_noteOrnament release];
  [_pendingDynamic release];
  [_pendingHairpinStart release];
  [_pendingDirectionText release];
  [_scoreTitle release];
  [_scoreTitleFontName release];
  [_scoreComposer release];
  [_currentKeyMode release];
  [_measureRehearsalMark release];
  [_measureEndingText release];
  [super dealloc];
}

- (ScoreDocument *)document
{
  return _document;
}

- (NSUInteger)tickForQuarterPosition:(double)position
{
  return (NSUInteger)MAX ((long long)0, llround (position * 480.0));
}

- (void)parser:(NSXMLParser *)parser
  didStartElement:(NSString *)element
     namespaceURI:(NSString *)namespaceURI
    qualifiedName:(NSString *)qualifiedName
       attributes:(NSDictionary *)attributes
{
  (void)parser;
  (void)namespaceURI;
  (void)qualifiedName;
  [_text setString:@""];
  if ([element isEqualToString:@"score-part"])
    {
      [_currentPartID release];
      _currentPartID = [[attributes objectForKey:@"id"] copy];
    }
  else if ([element isEqualToString:@"part"])
    {
      [_currentPartID release];
      _currentPartID = [[attributes objectForKey:@"id"] copy];
      NSNumber *track = [_partIndexes objectForKey:_currentPartID];
      if (!track)
        {
          track = [NSNumber numberWithUnsignedInteger:[_partIndexes count]];
          [_partIndexes setObject:track forKey:_currentPartID];
        }
      _currentTrack = [track integerValue];
      _currentQuarter = 0.0;
      _measureStartQuarter = 0.0;
      _measureMaxQuarter = 0.0;
      _currentMeasureIndex = -1;
      NSString *name = [_partNames objectForKey:_currentPartID];
      [_document setName:([name length]
                            ? name
                            : [NSString stringWithFormat:@"Part %ld", (long)(_currentTrack + 1)])
                forTrack:_currentTrack];
      NSNumber *program = [_partPrograms objectForKey:_currentPartID];
      if (program)
        [_document setProgram:program forTrack:_currentTrack];
    }
  else if ([element isEqualToString:@"measure"])
    {
      _currentQuarter = _measureStartQuarter;
      _measureMaxQuarter = _measureStartQuarter;
      _measureImplicit = [[attributes objectForKey:@"implicit"] isEqualToString:@"yes"];
      _currentMeasureNumberSpecified = [attributes objectForKey:@"number"] != nil;
      _currentMeasureNumber = [[attributes objectForKey:@"number"] integerValue];
      _currentMeasureIndex++;
      _measureRepeatStart = NO;
      _measureRepeatEnd = NO;
      _measureSystemBreak = NO;
      _measurePageBreak = NO;
      [_measureRehearsalMark release];
      _measureRehearsalMark = nil;
      [_measureEndingText release];
      _measureEndingText = nil;
    }
  else if ([element isEqualToString:@"print"])
    {
      _measureSystemBreak = [[attributes objectForKey:@"new-system"] isEqualToString:@"yes"];
      _measurePageBreak = [[attributes objectForKey:@"new-page"] isEqualToString:@"yes"];
      if (_measurePageBreak)
        _measureSystemBreak = YES;
    }
  else if ([element isEqualToString:@"note"])
    {
      _inNote = YES;
      _noteRest = NO;
      _noteChord = NO;
      _noteGrace = NO;
      _noteCue = NO;
      _noteTremoloStrokes = 0;
      _noteSlurStart = NO;
      _noteSlurEnd = NO;
      _noteTieStart = NO;
      _noteTieEnd = NO;
      _noteTupletActual = 0;
      _noteTupletNormal = 0;
      [_noteArticulation release];
      _noteArticulation = nil;
      [_noteLyric release];
      _noteLyric = nil;
      [_noteOrnament release];
      _noteOrnament = nil;
      _noteVoice = 1;
      _noteStaff = 0;
      _noteAlter = 0;
      _noteOctave = 4;
      _noteDurationQuarters = 1.0 / (double)MAX ((NSUInteger)1, _divisions);
      [_noteStep release];
      _noteStep = nil;
    }
  else if (_inNote && [element isEqualToString:@"rest"])
    {
      _noteRest = YES;
    }
  else if (_inNote && [element isEqualToString:@"chord"])
    {
      _noteChord = YES;
    }
  else if (_inNote && [element isEqualToString:@"grace"])
    {
      _noteGrace = YES;
      _noteDurationQuarters = 0.0;
    }
  else if (_inNote && [element isEqualToString:@"cue"])
    _noteCue = YES;
  else if (_inNote
           && ([element isEqualToString:@"trill-mark"] || [element isEqualToString:@"turn"] ||
               [element isEqualToString:@"mordent"] ||
               [element isEqualToString:@"inverted-mordent"]))
    {
      [_noteOrnament release];
      _noteOrnament = [element copy];
    }
  else if ([element isEqualToString:@"backup"])
    {
      _inBackup = YES;
    }
  else if ([element isEqualToString:@"forward"])
    {
      _inForward = YES;
    }
  else if (_inNote && [element isEqualToString:@"slur"])
    {
      NSString *type = [attributes objectForKey:@"type"];
      if ([type isEqualToString:@"start"])
        _noteSlurStart = YES;
      if ([type isEqualToString:@"stop"])
        _noteSlurEnd = YES;
    }
  else if (_inNote && [element isEqualToString:@"tie"])
    {
      NSString *type = [attributes objectForKey:@"type"];
      if ([type isEqualToString:@"start"])
        _noteTieStart = YES;
      if ([type isEqualToString:@"stop"])
        _noteTieEnd = YES;
    }
  else if (_inNote
           && ([element isEqualToString:@"staccato"] || [element isEqualToString:@"accent"] ||
               [element isEqualToString:@"tenuto"] || [element isEqualToString:@"strong-accent"]))
    {
      [_noteArticulation release];
      _noteArticulation = [element copy];
    }
  else if ([element isEqualToString:@"repeat"])
    {
      NSString *direction = [attributes objectForKey:@"direction"];
      if ([direction isEqualToString:@"forward"])
        _measureRepeatStart = YES;
      if ([direction isEqualToString:@"backward"])
        _measureRepeatEnd = YES;
    }
  else if ([element isEqualToString:@"ending"]
           && ![[attributes objectForKey:@"type"] isEqualToString:@"stop"])
    {
      [_measureEndingText release];
      _measureEndingText = [[attributes objectForKey:@"number"] copy];
    }
  else if ([element isEqualToString:@"dynamics"])
    {
      /* The child element name (p, mf, ff, …) is captured below. */
    }
  else if ([element isEqualToString:@"wedge"])
    {
      NSString *type = [attributes objectForKey:@"type"];
      if ([type isEqualToString:@"crescendo"] || [type isEqualToString:@"diminuendo"])
        {
          [_pendingHairpinStart release];
          _pendingHairpinStart = [type copy];
        }
      else if ([type isEqualToString:@"stop"])
        _pendingHairpinEnd = YES;
    }
  else if ([element isEqualToString:@"pedal"])
    {
      NSString *type = [attributes objectForKey:@"type"];
      if ([type isEqualToString:@"start"] || [type isEqualToString:@"resume"])
        _pendingPedalStart = YES;
      else if ([type isEqualToString:@"stop"] || [type isEqualToString:@"discontinue"])
        _pendingPedalEnd = YES;
    }
  else if ([element isEqualToString:@"octave-shift"])
    {
      NSString *type = [attributes objectForKey:@"type"];
      if ([type isEqualToString:@"down"])
        _pendingOctaveShiftStart = 1;
      else if ([type isEqualToString:@"up"])
        _pendingOctaveShiftStart = -1;
      else if ([type isEqualToString:@"stop"])
        _pendingOctaveShiftEnd = YES;
    }
  else if ([element isEqualToString:@"p"] || [element isEqualToString:@"pp"] ||
           [element isEqualToString:@"ppp"] || [element isEqualToString:@"mp"] ||
           [element isEqualToString:@"mf"] || [element isEqualToString:@"f"] ||
           [element isEqualToString:@"ff"] || [element isEqualToString:@"fff"] ||
           [element isEqualToString:@"sfz"])
    {
      [_pendingDynamic release];
      _pendingDynamic = [element copy];
    }
  else if ([element isEqualToString:@"sound"])
    {
      NSString *tempo = [attributes objectForKey:@"tempo"];
      if (!_foundTempo && [tempo doubleValue] > 0.0)
        {
          [_document
            setTempoMicrosecondsPerQuarter:(NSUInteger)llround (60000000.0 / [tempo doubleValue])];
          _foundTempo = YES;
        }
    }
  else if ([element isEqualToString:@"credit-words"])
    {
      NSString *fontFamily = [attributes objectForKey:@"font-family"];
      if ([fontFamily length])
        {
          [_scoreTitleFontName release];
          _scoreTitleFontName = [fontFamily copy];
        }
    }
  else if ([element isEqualToString:@"creator"])
    {
      NSString *type = [attributes objectForKey:@"type"];
      _inComposerCreator
        = ![type length] || [type caseInsensitiveCompare:@"composer"] == NSOrderedSame;
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
  (void)parser;
  [_text appendString:string];
}

- (void)parser:(NSXMLParser *)parser
  didEndElement:(NSString *)element
   namespaceURI:(NSString *)namespaceURI
  qualifiedName:(NSString *)qualifiedName
{
  (void)parser;
  (void)namespaceURI;
  (void)qualifiedName;
  NSString *value =
    [_text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([element isEqualToString:@"work-title"] || [element isEqualToString:@"movement-title"])
    {
      if ([value length])
        {
          [_scoreTitle release];
          _scoreTitle = [value copy];
        }
    }
  else if ([element isEqualToString:@"creator"])
    {
      if (_inComposerCreator && [value length])
        {
          [_scoreComposer release];
          _scoreComposer = [value copy];
        }
      _inComposerCreator = NO;
    }
  else if ([element isEqualToString:@"rehearsal"] && [value length])
    {
      [_measureRehearsalMark release];
      _measureRehearsalMark = [value copy];
    }
  else if ([element isEqualToString:@"words"] && [value length])
    {
      [_pendingDirectionText release];
      _pendingDirectionText = [value copy];
    }
  else if ([element isEqualToString:@"part-name"] && _currentPartID)
    {
      [_partNames setObject:value forKey:_currentPartID];
    }
  else if ([element isEqualToString:@"midi-program"] && _currentPartID)
    {
      NSInteger program = MAX ((NSInteger)1, MIN ((NSInteger)128, [value integerValue])) - 1;
      [_partPrograms setObject:[NSNumber numberWithInteger:program] forKey:_currentPartID];
    }
  else if ([element isEqualToString:@"per-minute"] && !_foundTempo && [value doubleValue] > 0.0)
    {
      [_document
        setTempoMicrosecondsPerQuarter:(NSUInteger)llround (60000000.0 / [value doubleValue])];
      _foundTempo = YES;
    }
  else if ([element isEqualToString:@"divisions"])
    {
      _divisions = MAX ((NSUInteger)1, (NSUInteger)[value integerValue]);
    }
  else if ([element isEqualToString:@"beats"])
    {
      [_document setTimeSignatureNumerator:MAX ((NSUInteger)1, (NSUInteger)[value integerValue])];
    }
  else if ([element isEqualToString:@"beat-type"])
    {
      [_document setTimeSignatureDenominator:MAX ((NSUInteger)1, (NSUInteger)[value integerValue])];
    }
  else if ([element isEqualToString:@"fifths"])
    {
      _currentKeyFifths = MIN (MAX ([value integerValue], (NSInteger)-7), (NSInteger)7);
    }
  else if ([element isEqualToString:@"mode"])
    {
      [_currentKeyMode release];
      NSString *mode = [[value lowercaseString] isEqualToString:@"minor"] ? @"minor" : @"major";
      _currentKeyMode = [mode copy];
    }
  else if (_inNote && [element isEqualToString:@"step"])
    {
      [_noteStep release];
      _noteStep = [[value uppercaseString] copy];
    }
  else if (_inNote && [element isEqualToString:@"alter"])
    {
      _noteAlter = [value integerValue];
    }
  else if (_inNote && [element isEqualToString:@"octave"])
    {
      _noteOctave = [value integerValue];
    }
  else if (_inNote && [element isEqualToString:@"voice"])
    {
      _noteVoice = MAX ((NSInteger)1, [value integerValue]);
    }
  else if (_inNote && [element isEqualToString:@"staff"])
    {
      _noteStaff = MIN (MAX ([value integerValue], (NSInteger)0), (NSInteger)2);
    }
  else if (_inNote && [element isEqualToString:@"actual-notes"])
    {
      _noteTupletActual = MAX ((NSUInteger)1, (NSUInteger)[value integerValue]);
    }
  else if (_inNote && [element isEqualToString:@"normal-notes"])
    {
      _noteTupletNormal = MAX ((NSUInteger)1, (NSUInteger)[value integerValue]);
    }
  else if (_inNote && [element isEqualToString:@"text"] && [value length])
    {
      [_noteLyric release];
      _noteLyric = [value copy];
    }
  else if (_inNote && [element isEqualToString:@"tremolo"])
    _noteTremoloStrokes = MIN ((NSUInteger)4, (NSUInteger)MAX ((NSInteger)0, [value integerValue]));
  else if ([element isEqualToString:@"duration"])
    {
      double duration = (double)MAX ((NSInteger)1, [value integerValue])
                        / (double)MAX ((NSUInteger)1, _divisions);
      if (_inNote)
        {
          _noteDurationQuarters = duration;
        }
      else if (_inBackup)
        {
          _currentQuarter = MAX (_measureStartQuarter, _currentQuarter - duration);
        }
      else if (_inForward)
        {
          _currentQuarter += duration;
          _measureMaxQuarter = MAX (_measureMaxQuarter, _currentQuarter);
        }
    }
  else if ([element isEqualToString:@"note"])
    {
      double startQuarter = _noteChord ? _lastNoteStartQuarter : _currentQuarter;
      double endQuarter = startQuarter + _noteDurationQuarters;
      NSUInteger start = [self tickForQuarterPosition:startQuarter];
      NSUInteger end = [self tickForQuarterPosition:endQuarter];
      ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
      [note setRest:_noteRest];
      NSInteger pitch
        = _noteRest ? 60 : ((_noteOctave + 1) * 12 + PitchClassForStep (_noteStep) + _noteAlter);
      [note setPitch:MIN (MAX (pitch, (NSInteger)0), (NSInteger)127)];
      [note setAccidental:MIN (MAX (_noteAlter, (NSInteger)-1), (NSInteger)1)];
      [note setTrack:_currentTrack];
      [note setChannel:_currentTrack % 16];
      [note setStartTick:start];
      [note setDurationTicks:MAX ((NSUInteger)1, end - start)];
      [note setSlurStart:_noteSlurStart];
      [note setSlurEnd:_noteSlurEnd];
      [note setTieStart:_noteTieStart];
      [note setTieEnd:_noteTieEnd];
      [note setTupletActual:_noteTupletActual];
      [note setTupletNormal:_noteTupletNormal];
      [note setArticulation:_noteArticulation];
      [note setLyric:_noteLyric];
      [note setOrnament:_noteOrnament];
      [note setGrace:_noteGrace];
      [note setCue:_noteCue];
      [note setTremoloStrokes:_noteTremoloStrokes];
      [note setHairpinStart:_pendingHairpinStart];
      [note setHairpinEnd:_pendingHairpinEnd];
      [note setPedalStart:_pendingPedalStart];
      [note setPedalEnd:_pendingPedalEnd];
      [note setOctaveShiftStart:_pendingOctaveShiftStart];
      [note setOctaveShiftEnd:_pendingOctaveShiftEnd];
      [note setDirectionText:_pendingDirectionText];
      [_pendingHairpinStart release];
      _pendingHairpinStart = nil;
      _pendingHairpinEnd = NO;
      _pendingPedalStart = NO;
      _pendingPedalEnd = NO;
      _pendingOctaveShiftStart = 0;
      _pendingOctaveShiftEnd = NO;
      [_pendingDirectionText release];
      _pendingDirectionText = nil;
      [note setDynamic:_pendingDynamic];
      if ([_pendingDynamic length])
        {
          [_pendingDynamic release];
          _pendingDynamic = nil;
        }
      [note setVoice:_noteVoice];
      [note setStaffAssignment:_noteStaff];
      [note setMeasureIndex:_currentMeasureIndex];
      [[_document notes] addObject:note];
      _lastNoteStartQuarter = startQuarter;
      if (!_noteChord && !_noteGrace)
        _currentQuarter += _noteDurationQuarters;
      _measureMaxQuarter = MAX (_measureMaxQuarter, endQuarter);
      [_document setTotalTicks:MAX ([_document totalTicks], end)];
      _inNote = NO;
    }
  else if ([element isEqualToString:@"backup"])
    {
      _inBackup = NO;
    }
  else if ([element isEqualToString:@"forward"])
    {
      _inForward = NO;
    }
  else if ([element isEqualToString:@"measure"])
    {
      double measureQuarters = 4.0 * (double)[_document timeSignatureNumerator]
                               / (double)MAX ((NSUInteger)1, [_document timeSignatureDenominator]);
      double nominalEnd = _measureStartQuarter + measureQuarters;
      double actualEnd = _measureImplicit ? _measureMaxQuarter : nominalEnd;
      if (_currentTrack == 0)
        {
          ScoreMeasure *measure = [[[ScoreMeasure alloc] init] autorelease];
          [measure setNumber:_currentMeasureNumberSpecified ? _currentMeasureNumber
                                                            : _currentMeasureIndex + 1];
          [measure setStartTick:[self tickForQuarterPosition:_measureStartQuarter]];
          [measure setDurationTicks:MAX ((NSUInteger)1,
                                         [self tickForQuarterPosition:actualEnd] -
                                           [self tickForQuarterPosition:_measureStartQuarter])];
          [measure setTimeSignatureNumerator:[_document timeSignatureNumerator]];
          [measure setTimeSignatureDenominator:[_document timeSignatureDenominator]];
          [measure setImplicit:_measureImplicit];
          [measure setKeySignatureFifths:_currentKeyFifths];
          [measure setKeyMode:_currentKeyMode];
          [measure setRepeatStart:_measureRepeatStart];
          [measure setRepeatEnd:_measureRepeatEnd];
          [measure setRehearsalMark:_measureRehearsalMark];
          [measure setEndingText:_measureEndingText];
          [measure setSystemBreak:_measureSystemBreak];
          [measure setPageBreak:_measurePageBreak];
          [[_document measures] addObject:measure];
        }
      // Notes may legitimately sound across a barline. Their end positions must
      // not lengthen a regular measure or every following measure will drift.
      _measureStartQuarter = actualEnd;
      _currentQuarter = _measureStartQuarter;
    }
}

- (void)parserDidEndDocument:(NSXMLParser *)parser
{
  (void)parser;
  if ([_scoreTitle length])
    [_document setTitle:_scoreTitle];
  if ([_scoreTitleFontName length])
    [_document setTitleFontName:_scoreTitleFontName];
  if ([_scoreComposer length])
    [_document setComposer:_scoreComposer];
  [[_document notes] sortUsingSelector:@selector (compareScoreNote:)];
}

@end

@implementation MusicXMLParser

+ (ScoreDocument *)parseFileAtPath:(NSString *)path error:(NSError **)error
{
  NSData *data = [NSData dataWithContentsOfFile:path];
  if (!data)
    {
      if (error)
        *error = [NSError
          errorWithDomain:MusicXMLErrorDomain
                     code:1
                 userInfo:[NSDictionary dictionaryWithObject:@"The MusicXML file could not be read."
                                                      forKey:NSLocalizedDescriptionKey]];
      return nil;
    }
  NSXMLParser *parser = [[[NSXMLParser alloc] initWithData:data] autorelease];
  MusicXMLImportDelegate *delegate = [[[MusicXMLImportDelegate alloc] init] autorelease];
  [parser setDelegate:delegate];
  if (![parser parse])
    {
      if (error)
        *error = [parser parserError];
      return nil;
    }
  [[delegate document] rebuildStructuredPartsFromLegacyTracks];
  return [delegate document];
}

+ (NSData *)dataForDocument:(ScoreDocument *)document error:(NSError **)error
{
  if (!document)
    {
      if (error)
        *error = [NSError
          errorWithDomain:MusicXMLErrorDomain
                     code:2
                 userInfo:[NSDictionary dictionaryWithObject:@"There is no score to export."
                                                      forKey:NSLocalizedDescriptionKey]];
      return nil;
    }
  NSMutableSet *trackSet = [NSMutableSet setWithArray:[[document partNames] allKeys]];
  [trackSet addObjectsFromArray:[[document trackPrograms] allKeys]];
  for (ScoreNote *note in [document notes])
    [trackSet addObject:[NSNumber numberWithInteger:[note track]]];
  if ([trackSet count] == 0)
    [trackSet addObject:[NSNumber numberWithInteger:0]];
  NSArray *tracks = [[trackSet allObjects] sortedArrayUsingSelector:@selector (compare:)];

  NSMutableString *xml =
    [NSMutableString stringWithString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
  [xml appendString:@"<!DOCTYPE score-partwise PUBLIC \"-//Recordare//DTD MusicXML 4.0 "
                    @"Partwise//EN\" \"http://www.musicxml.org/dtds/partwise.dtd\">\n"];
  [xml appendString:@"<score-partwise version=\"4.0\">\n"];
  [xml appendFormat:@"  <work><work-title>%@</work-title></work>\n",
                    EscapeXML ([document title] ?: @"Untitled")];
  if ([[document composer] length] > 0)
    {
      [xml appendFormat:
             @"  <identification><creator type=\"composer\">%@</creator></identification>\n",
             EscapeXML ([document composer])];
    }
  if ([[document titleFontName] length] > 0)
    {
      [xml appendFormat:
             @"  <credit page=\"1\"><credit-words font-family=\"%@\">%@</credit-words></credit>\n",
             EscapeXML ([document titleFontName]), EscapeXML ([document title] ?: @"Untitled")];
    }
  [xml appendString:@"  <part-list>\n"];
  for (NSUInteger i = 0; i < [tracks count]; i++)
    {
      NSInteger track = [[tracks objectAtIndex:i] integerValue];
      NSString *partID = [NSString stringWithFormat:@"P%lu", (unsigned long)(i + 1)];
      NSString *name =
        [document nameForTrack:track] ?: [NSString stringWithFormat:@"Part %ld", (long)(track + 1)];
      NSInteger program = [[document programForTrack:track] integerValue];
      [xml appendFormat:@"    <score-part id=\"%@\"><part-name>%@</part-name><midi-instrument "
                        @"id=\"%@-I1\"><midi-channel>%ld</midi-channel><midi-program>%ld</"
                        @"midi-program></midi-instrument></score-part>\n",
                        partID, EscapeXML (name), partID, (long)(track % 16 + 1),
                        (long)(program + 1)];
    }
  [xml appendString:@"  </part-list>\n"];

  NSUInteger tpq = MAX ((NSUInteger)1, [document ticksPerQuarter]);
  if ([[document measures] count] == 0)
    [document buildDefaultMeasures];
  NSArray *measures = [document measures];
  for (NSUInteger i = 0; i < [tracks count]; i++)
    {
      NSInteger track = [[tracks objectAtIndex:i] integerValue];
      [xml appendFormat:@"  <part id=\"P%lu\">\n", (unsigned long)(i + 1)];
      for (NSUInteger measureIndex = 0; measureIndex < [measures count]; measureIndex++)
        {
          ScoreMeasure *measure = [measures objectAtIndex:measureIndex];
          NSUInteger measureStart = [measure startTick];
          NSUInteger measureEnd = measureStart + [measure durationTicks];
          [xml appendFormat:@"    <measure number=\"%ld\"%@>\n", (long)[measure number],
                            [measure isImplicit] ? @" implicit=\"yes\"" : @""];
          BOOL timeChanged = measureIndex == 0;
          BOOL keyChanged = measureIndex == 0;
          if (measureIndex > 0)
            {
              ScoreMeasure *previous = [measures objectAtIndex:measureIndex - 1];
              timeChanged =
                [previous timeSignatureNumerator] != [measure timeSignatureNumerator] ||
                [previous timeSignatureDenominator] != [measure timeSignatureDenominator];
              keyChanged = [previous keySignatureFifths] != [measure keySignatureFifths];
              keyChanged = keyChanged || ![[previous keyMode] isEqualToString:[measure keyMode]];
            }
          if (timeChanged || keyChanged)
            {
              [xml
                appendFormat:@"      <attributes><divisions>%lu</divisions>", (unsigned long)tpq];
              if (keyChanged)
                [xml appendFormat:@"<key><fifths>%ld</fifths><mode>%@</mode></key>",
                                  (long)[measure keySignatureFifths], [measure keyMode]];
              if (timeChanged)
                [xml appendFormat:@"<time><beats>%lu</beats><beat-type>%lu</beat-type></time>",
                                  (unsigned long)[measure timeSignatureNumerator],
                                  (unsigned long)[measure timeSignatureDenominator]];
              [xml appendString:@"<clef><sign>G</sign><line>2</line></clef></attributes>\n"];
            }
          if ([measure repeatStart])
            [xml appendString:
                   @"      <barline location=\"left\"><repeat direction=\"forward\"/></barline>\n"];
          if ([measure pageBreak])
            [xml appendString:@"      <print new-page=\"yes\"/>\n"];
          else if ([measure systemBreak])
            [xml appendString:@"      <print new-system=\"yes\"/>\n"];
          if ([[measure rehearsalMark] length])
            [xml appendFormat:@"      <direction "
                              @"placement=\"above\"><direction-type><rehearsal>%@</rehearsal></"
                              @"direction-type></direction>\n",
                              EscapeXML ([measure rehearsalMark])];
          if ([[measure endingText] length])
            [xml appendFormat:@"      <barline location=\"left\"><ending number=\"%@\" "
                              @"type=\"start\"/></barline>\n",
                              EscapeXML ([measure endingText])];
          if (measureIndex == 0)
            {
              double bpm = [document tempoMicrosecondsPerQuarter]
                             ? 60000000.0 / [document tempoMicrosecondsPerQuarter]
                             : 120.0;
              [xml appendFormat:
                     @"      <direction placement=\"above\"><sound tempo=\"%.6g\"/></direction>\n",
                     bpm];
            }
          NSMutableSet *voiceSet = [NSMutableSet set];
          for (ScoreNote *note in [document notes])
            {
              if ([note track] == track && [note startTick] >= measureStart &&
                  [note startTick] < measureEnd)
                [voiceSet addObject:[NSNumber numberWithInteger:[note voice]]];
            }
          NSArray *voices = [[voiceSet allObjects] sortedArrayUsingSelector:@selector (compare:)];
          if ([voices count] == 0 && [measure isImplicit])
            {
              [xml appendFormat:@"      <forward><duration>%lu</duration></forward>\n",
                                (unsigned long)[measure durationTicks]];
            }
          for (NSNumber *voiceNumber in voices)
            {
              NSInteger cursor = 0;
              for (ScoreNote *note in [document notes])
                {
                  if ([note track] != track || [note voice] != [voiceNumber integerValue] ||
                      [note startTick] < measureStart || [note startTick] >= measureEnd)
                    continue;
                  NSInteger onset = (NSInteger)([note startTick] - measureStart);
                  NSInteger movement = onset - cursor;
                  if (movement > 0)
                    [xml appendFormat:@"      <forward><duration>%ld</duration></forward>\n",
                                      (long)movement];
                  if (movement < 0)
                    [xml appendFormat:@"      <backup><duration>%ld</duration></backup>\n",
                                      (long)-movement];
                  if ([[note dynamic] length])
                    [xml appendFormat:@"      <direction "
                                      @"placement=\"below\"><direction-type><dynamics><%@/></"
                                      @"dynamics></direction-type></direction>\n",
                                      [note dynamic]];
                  if ([[note hairpinStart] length])
                    [xml
                      appendFormat:@"      <direction placement=\"below\"><direction-type><wedge "
                                   @"type=\"%@\"/></direction-type></direction>\n",
                                   [note hairpinStart]];
                  if ([note hairpinEnd])
                    [xml
                      appendString:@"      <direction placement=\"below\"><direction-type><wedge "
                                   @"type=\"stop\"/></direction-type></direction>\n"];
                  if ([note pedalStart] || [note pedalEnd])
                    [xml
                      appendFormat:@"      <direction placement=\"below\"><direction-type><pedal "
                                   @"type=\"%@\" line=\"yes\"/></direction-type></direction>\n",
                                   [note pedalStart] ? @"start" : @"stop"];
                  if ([note octaveShiftStart] || [note octaveShiftEnd])
                    [xml appendFormat:
                           @"      <direction placement=\"above\"><direction-type><octave-shift "
                           @"type=\"%@\" size=\"8\"/></direction-type></direction>\n",
                           [note octaveShiftEnd] ? @"stop"
                                                 : ([note octaveShiftStart] > 0 ? @"down" : @"up")];
                  if ([[note directionText] length])
                    [xml appendFormat:@"      <direction "
                                      @"placement=\"above\"><direction-type><words>%@</words></"
                                      @"direction-type></direction>\n",
                                      EscapeXML ([note directionText])];
                  [xml appendString:@"      <note>"];
                  if ([note isGrace])
                    [xml appendString:@"<grace/>"];
                  if ([note isCue])
                    [xml appendString:@"<cue/>"];
                  NSInteger accidental = [note accidental];
                  if ([note isRest])
                    {
                      [xml appendString:@"<rest/>"];
                    }
                  else
                    {
                      NSInteger naturalPitch = [note pitch] - accidental;
                      NSInteger octave = naturalPitch / 12 - 1;
                      [xml appendFormat:@"<pitch><step>%@</step>",
                                        StepForPitch ([note pitch], accidental)];
                      if (accidental)
                        [xml appendFormat:@"<alter>%ld</alter>", (long)accidental];
                      [xml appendFormat:@"<octave>%ld</octave></pitch>", (long)octave];
                    }
                  if (![note isGrace])
                    [xml appendFormat:@"<duration>%lu</duration>",
                                      (unsigned long)MAX ((NSUInteger)1, [note durationTicks])];
                  [xml appendFormat:@"<voice>%ld</voice>", (long)[note voice]];
                  if ([note staffAssignment])
                    [xml appendFormat:@"<staff>%ld</staff>", (long)[note staffAssignment]];
                  if ([note tieEnd])
                    [xml appendString:@"<tie type=\"stop\"/>"];
                  if ([note tieStart])
                    [xml appendString:@"<tie type=\"start\"/>"];
                  if ([note tupletActual] && [note tupletNormal])
                    [xml appendFormat:
                           @"<time-modification><actual-notes>%lu</actual-notes><normal-notes>%lu</"
                           @"normal-notes></time-modification>",
                           (unsigned long)[note tupletActual], (unsigned long)[note tupletNormal]];
                  if (![note isRest] && accidental)
                    {
                      [xml appendFormat:@"<accidental>%@</accidental>",
                                        accidental > 0 ? @"sharp" : @"flat"];
                    }
                  if ([note slurStart] || [note slurEnd] || [[note articulation] length] ||
                      [[note ornament] length] || [note tremoloStrokes])
                    {
                      [xml appendString:@"<notations>"];
                      if ([note slurStart])
                        [xml appendString:@"<slur type=\"start\"/>"];
                      if ([note slurEnd])
                        [xml appendString:@"<slur type=\"stop\"/>"];
                      if ([[note articulation] length])
                        [xml appendFormat:@"<articulations><%@/></articulations>",
                                          [note articulation]];
                      if ([[note ornament] length] || [note tremoloStrokes])
                        {
                          [xml appendString:@"<ornaments>"];
                          if ([[note ornament] length])
                            [xml appendFormat:@"<%@/>", [note ornament]];
                          if ([note tremoloStrokes])
                            [xml appendFormat:@"<tremolo>%lu</tremolo>",
                                              (unsigned long)[note tremoloStrokes]];
                          [xml appendString:@"</ornaments>"];
                        }
                      [xml appendString:@"</notations>"];
                    }
                  if ([[note lyric] length])
                    [xml appendFormat:@"<lyric><text>%@</text></lyric>", EscapeXML ([note lyric])];
                  [xml appendString:@"</note>\n"];
                  cursor = onset + (NSInteger)[note durationTicks];
                }
              if ([voiceNumber integerValue] != [[voices lastObject] integerValue] && cursor > 0)
                {
                  [xml appendFormat:@"      <backup><duration>%ld</duration></backup>\n",
                                    (long)cursor];
                }
            }
          if ([measure repeatEnd])
            [xml
              appendString:
                @"      <barline location=\"right\"><repeat direction=\"backward\"/></barline>\n"];
          [xml appendString:@"    </measure>\n"];
        }
      [xml appendString:@"  </part>\n"];
    }
  [xml appendString:@"</score-partwise>\n"];
  NSData *data = [xml dataUsingEncoding:NSUTF8StringEncoding];
  if (!data && error)
    {
      *error = [NSError
        errorWithDomain:MusicXMLErrorDomain
                   code:3
               userInfo:[NSDictionary
                          dictionaryWithObject:@"The MusicXML document could not be encoded."
                                        forKey:NSLocalizedDescriptionKey]];
    }
  return data;
}

@end
