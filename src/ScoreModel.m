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

#import "ScoreModel.h"
#import "MusicPlatformModel.h"

@implementation ScoreNote

- (id)init
{
  self = [super init];
  if (self)
    {
      _voice = 1;
      _measureIndex = -1;
      _velocity = 64;
    }
  return self;
}

static NSInteger
DefaultAccidentalForPitch (NSInteger pitch)
{
  NSInteger pitchClass = pitch % 12;
  if (pitchClass < 0)
    pitchClass += 12;
  switch (pitchClass)
    {
    case 1:
    case 6:
      return 1;
    case 3:
    case 8:
    case 10:
      return -1;
    default:
      return 0;
    }
}

- (NSInteger)pitch
{
  return _pitch;
}

- (void)setPitch:(NSInteger)pitch
{
  _pitch = pitch;
  _accidental = DefaultAccidentalForPitch (pitch);
}

- (NSInteger)channel
{
  return _channel;
}

- (void)setChannel:(NSInteger)channel
{
  _channel = channel;
}

- (NSInteger)track
{
  return _track;
}

- (void)setTrack:(NSInteger)track
{
  _track = track;
}

- (NSUInteger)startTick
{
  return _startTick;
}

- (void)setStartTick:(NSUInteger)startTick
{
  _startTick = startTick;
}

- (NSUInteger)durationTicks
{
  return _durationTicks;
}

- (void)setDurationTicks:(NSUInteger)durationTicks
{
  _durationTicks = durationTicks;
}

- (BOOL)isRest
{
  return _rest;
}

- (void)setRest:(BOOL)rest
{
  _rest = rest;
}

- (NSInteger)accidental
{
  return _accidental;
}

- (void)setAccidental:(NSInteger)accidental
{
  _accidental = MIN (MAX (accidental, (NSInteger)-1), (NSInteger)1);
}

- (BOOL)slurStart
{
  return _slurStart;
}

- (void)setSlurStart:(BOOL)slurStart
{
  _slurStart = slurStart;
}

- (BOOL)slurEnd
{
  return _slurEnd;
}

- (void)setSlurEnd:(BOOL)slurEnd
{
  _slurEnd = slurEnd;
}

- (BOOL)tieStart
{
  return _tieStart;
}
- (void)setTieStart:(BOOL)value
{
  _tieStart = value;
}
- (BOOL)tieEnd
{
  return _tieEnd;
}
- (void)setTieEnd:(BOOL)value
{
  _tieEnd = value;
}
- (NSUInteger)tupletActual
{
  return _tupletActual;
}
- (void)setTupletActual:(NSUInteger)value
{
  _tupletActual = value;
}
- (NSUInteger)tupletNormal
{
  return _tupletNormal;
}
- (void)setTupletNormal:(NSUInteger)value
{
  _tupletNormal = value;
}
- (NSString *)dynamic
{
  return _dynamic;
}
- (void)setDynamic:(NSString *)value
{
  if (_dynamic != value)
    {
      [_dynamic release];
      _dynamic = [value copy];
    }
}
- (NSString *)articulation
{
  return _articulation;
}
- (void)setArticulation:(NSString *)value
{
  if (_articulation != value)
    {
      [_articulation release];
      _articulation = [value copy];
    }
}
- (NSString *)lyric { return _lyric; }
- (void)setLyric:(NSString *)value
{
  if (_lyric != value) { [_lyric release]; _lyric = [value copy]; }
}
- (NSString *)ornament { return _ornament; }
- (void)setOrnament:(NSString *)value
{
  if (_ornament != value) { [_ornament release]; _ornament = [value copy]; }
}
- (BOOL)isGrace { return _grace; }
- (void)setGrace:(BOOL)value { _grace = value; }
- (BOOL)isCue { return _cue; }
- (void)setCue:(BOOL)value { _cue = value; }
- (NSUInteger)tremoloStrokes { return _tremoloStrokes; }
- (void)setTremoloStrokes:(NSUInteger)value { _tremoloStrokes = MIN ((NSUInteger)4, value); }
- (NSString *)hairpinStart { return _hairpinStart; }
- (void)setHairpinStart:(NSString *)value
{
  NSString *normalized = ([value isEqualToString:@"crescendo"] ||
                          [value isEqualToString:@"diminuendo"]) ? value : nil;
  if (_hairpinStart != normalized) { [_hairpinStart release]; _hairpinStart = [normalized copy]; }
}
- (BOOL)hairpinEnd { return _hairpinEnd; }
- (void)setHairpinEnd:(BOOL)value { _hairpinEnd = value; }
- (BOOL)pedalStart { return _pedalStart; }
- (void)setPedalStart:(BOOL)value { _pedalStart = value; }
- (BOOL)pedalEnd { return _pedalEnd; }
- (void)setPedalEnd:(BOOL)value { _pedalEnd = value; }
- (NSInteger)octaveShiftStart { return _octaveShiftStart; }
- (void)setOctaveShiftStart:(NSInteger)value { _octaveShiftStart = MIN ((NSInteger)1, MAX ((NSInteger)-1, value)); }
- (BOOL)octaveShiftEnd { return _octaveShiftEnd; }
- (void)setOctaveShiftEnd:(BOOL)value { _octaveShiftEnd = value; }
- (NSString *)directionText { return _directionText; }
- (void)setDirectionText:(NSString *)value
{
  if (_directionText != value) { [_directionText release]; _directionText = [value copy]; }
}
- (NSInteger)staffAssignment { return _staffAssignment; }
- (void)setStaffAssignment:(NSInteger)value
{
  _staffAssignment = MIN (MAX (value, (NSInteger)0), (NSInteger)2);
}

- (NSInteger)voice
{
  return _voice;
}
- (void)setVoice:(NSInteger)voice
{
  _voice = MAX ((NSInteger)1, voice);
}
- (NSInteger)measureIndex
{
  return _measureIndex;
}
- (void)setMeasureIndex:(NSInteger)measureIndex
{
  _measureIndex = MAX ((NSInteger)-1, measureIndex);
}
- (NSUInteger)velocity
{
  return _velocity;
}
- (void)setVelocity:(NSUInteger)velocity
{
  _velocity = MIN ((NSUInteger)127, velocity);
}
- (NSString *)provenance
{
  return _provenance;
}
- (void)setProvenance:(NSString *)provenance
{
  if (_provenance != provenance)
    {
      [_provenance release];
      _provenance = [provenance copy];
    }
}

- (NSComparisonResult)compareScoreNote:(ScoreNote *)other
{
  if (_startTick < [other startTick])
    return NSOrderedAscending;
  if (_startTick > [other startTick])
    return NSOrderedDescending;
  if (_voice < [other voice])
    return NSOrderedAscending;
  if (_voice > [other voice])
    return NSOrderedDescending;
  if (_rest && ![other isRest])
    return NSOrderedDescending;
  if (!_rest && [other isRest])
    return NSOrderedAscending;
  if (_pitch > [other pitch])
    return NSOrderedAscending;
  if (_pitch < [other pitch])
    return NSOrderedDescending;
  return NSOrderedSame;
}

- (id)copyWithZone:(NSZone *)zone
{
  ScoreNote *copy = [[ScoreNote allocWithZone:zone] init];
  [copy setPitch:_pitch];
  [copy setAccidental:_accidental];
  [copy setChannel:_channel];
  [copy setTrack:_track];
  [copy setStartTick:_startTick];
  [copy setDurationTicks:_durationTicks];
  [copy setRest:_rest];
  [copy setSlurStart:_slurStart];
  [copy setSlurEnd:_slurEnd];
  [copy setTieStart:_tieStart];
  [copy setTieEnd:_tieEnd];
  [copy setTupletActual:_tupletActual];
  [copy setTupletNormal:_tupletNormal];
  [copy setDynamic:_dynamic];
  [copy setArticulation:_articulation];
  [copy setLyric:_lyric];
  [copy setOrnament:_ornament];
  [copy setGrace:_grace];
  [copy setCue:_cue];
  [copy setTremoloStrokes:_tremoloStrokes];
  [copy setHairpinStart:_hairpinStart];
  [copy setHairpinEnd:_hairpinEnd];
  [copy setPedalStart:_pedalStart];
  [copy setPedalEnd:_pedalEnd];
  [copy setOctaveShiftStart:_octaveShiftStart];
  [copy setOctaveShiftEnd:_octaveShiftEnd];
  [copy setDirectionText:_directionText];
  [copy setStaffAssignment:_staffAssignment];
  [copy setVoice:_voice];
  [copy setMeasureIndex:_measureIndex];
  [copy setVelocity:_velocity];
  [copy setProvenance:_provenance];
  return copy;
}

- (void)dealloc
{
  [_dynamic release];
  [_articulation release];
  [_lyric release];
  [_ornament release];
  [_hairpinStart release];
  [_directionText release];
  [_provenance release];
  [super dealloc];
}

@end

@implementation ScoreMeasure
- (id)init
{
  self = [super init];
  if (self)
    _keyMode = [@"major" copy];
  return self;
}
- (NSInteger)number
{
  return _number;
}
- (void)setNumber:(NSInteger)number
{
  _number = number;
}
- (NSUInteger)startTick
{
  return _startTick;
}
- (void)setStartTick:(NSUInteger)startTick
{
  _startTick = startTick;
}
- (NSUInteger)durationTicks
{
  return _durationTicks;
}
- (void)setDurationTicks:(NSUInteger)durationTicks
{
  _durationTicks = durationTicks;
}
- (NSUInteger)timeSignatureNumerator
{
  return _timeSignatureNumerator;
}
- (void)setTimeSignatureNumerator:(NSUInteger)value
{
  _timeSignatureNumerator = MAX ((NSUInteger)1, value);
}
- (NSUInteger)timeSignatureDenominator
{
  return _timeSignatureDenominator;
}
- (void)setTimeSignatureDenominator:(NSUInteger)value
{
  _timeSignatureDenominator = MAX ((NSUInteger)1, value);
}
- (BOOL)isImplicit
{
  return _implicit;
}
- (void)setImplicit:(BOOL)implicit
{
  _implicit = implicit;
}
- (NSInteger)keySignatureFifths
{
  return _keySignatureFifths;
}
- (void)setKeySignatureFifths:(NSInteger)value
{
  _keySignatureFifths = MIN (MAX (value, (NSInteger)-7), (NSInteger)7);
}
- (NSString *)keyMode
{
  return _keyMode ?: @"major";
}
- (void)setKeyMode:(NSString *)value
{
  NSString *normalized = [[value lowercaseString] isEqualToString:@"minor"] ? @"minor" : @"major";
  if (_keyMode != normalized)
    {
      [_keyMode release];
      _keyMode = [normalized copy];
    }
}
- (BOOL)repeatStart
{
  return _repeatStart;
}
- (void)setRepeatStart:(BOOL)value
{
  _repeatStart = value;
}
- (BOOL)repeatEnd
{
  return _repeatEnd;
}
- (void)setRepeatEnd:(BOOL)value
{
  _repeatEnd = value;
}
- (NSString *)rehearsalMark { return _rehearsalMark; }
- (void)setRehearsalMark:(NSString *)value
{
  if (_rehearsalMark != value) { [_rehearsalMark release]; _rehearsalMark = [value copy]; }
}
- (NSString *)endingText { return _endingText; }
- (void)setEndingText:(NSString *)value
{
  if (_endingText != value) { [_endingText release]; _endingText = [value copy]; }
}
- (BOOL)systemBreak { return _systemBreak; }
- (void)setSystemBreak:(BOOL)value { _systemBreak = value; }
- (BOOL)pageBreak { return _pageBreak; }
- (void)setPageBreak:(BOOL)value
{
  _pageBreak = value;
  if (value)
    _systemBreak = YES;
}
- (id)copyWithZone:(NSZone *)zone
{
  ScoreMeasure *copy = [[ScoreMeasure allocWithZone:zone] init];
  [copy setNumber:_number];
  [copy setStartTick:_startTick];
  [copy setDurationTicks:_durationTicks];
  [copy setTimeSignatureNumerator:_timeSignatureNumerator];
  [copy setTimeSignatureDenominator:_timeSignatureDenominator];
  [copy setImplicit:_implicit];
  [copy setKeySignatureFifths:_keySignatureFifths];
  [copy setKeyMode:[self keyMode]];
  [copy setRepeatStart:_repeatStart];
  [copy setRepeatEnd:_repeatEnd];
  [copy setRehearsalMark:_rehearsalMark];
  [copy setEndingText:_endingText];
  [copy setSystemBreak:_systemBreak];
  [copy setPageBreak:_pageBreak];
  return copy;
}
- (void)dealloc
{
  [_keyMode release];
  [_rehearsalMark release];
  [_endingText release];
  [super dealloc];
}
@end

NSInteger
ScoreKeySignatureAlterationForStep (NSInteger fifths, NSInteger step)
{
  static NSInteger sharpOrder[] = { 3, 0, 4, 1, 5, 2, 6 }; /* F C G D A E B */
  static NSInteger flatOrder[] = { 6, 2, 5, 1, 4, 0, 3 };  /* B E A D G C F */
  step = ((step % 7) + 7) % 7;
  NSInteger count = labs (fifths);
  for (NSInteger i = 0; i < count; i++)
    if ((fifths > 0 ? sharpOrder[i] : flatOrder[i]) == step)
      return fifths > 0 ? 1 : -1;
  return 0;
}

static NSInteger
DiatonicStepAndOctaveForNote (ScoreNote *note, NSInteger *octave)
{
  static NSInteger pitchClassToStep[] = { 0, 0, 1, 2, 2, 3, 3, 4, 5, 5, 6, 6 };
  NSInteger naturalPitch = [note pitch] - [note accidental];
  NSInteger pitchClass = ((naturalPitch % 12) + 12) % 12;
  if (octave)
    *octave = naturalPitch / 12 - 1;
  return pitchClassToStep[pitchClass];
}

NSInteger
ScoreDisplayedAccidentalForNote (ScoreNote *note, ScoreDocument *document)
{
  NSNumber *value = [ScoreDisplayedAccidentalMapForDocument (document)
    objectForKey:[NSValue valueWithPointer:note]];
  return value ? [value integerValue] : NSIntegerMax;
}

NSDictionary *
ScoreDisplayedAccidentalMapForDocument (ScoreDocument *document)
{
  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  if (!document)
    return result;
  NSArray *notes = [[document notes] sortedArrayUsingSelector:@selector (compareScoreNote:)];
  NSArray *measures = [document measures];
  NSUInteger measureIndex = 0;
  NSMutableDictionary *state = [NSMutableDictionary dictionary];
  NSUInteger index = 0;
  while (index < [notes count])
    {
      ScoreNote *first = [notes objectAtIndex:index];
      NSUInteger onset = [first startTick];
      while (measureIndex + 1 < [measures count] &&
             onset >= [[measures objectAtIndex:measureIndex + 1] startTick])
        { measureIndex++; [state removeAllObjects]; }
      ScoreMeasure *measure = [measures count] ? [measures objectAtIndex:measureIndex] : nil;
      NSUInteger end = index;
      while (end < [notes count] && [[notes objectAtIndex:end] startTick] == onset) end++;
      for (NSUInteger i = index; i < end; i++)
        {
          ScoreNote *note = [notes objectAtIndex:i];
          if ([note isRest]) continue;
          NSInteger octave = 0, step = DiatonicStepAndOctaveForNote (note, &octave);
          NSString *key = [NSString stringWithFormat:@"%ld:%ld:%ld", (long)[note track],
                                                   (long)step, (long)octave];
          NSNumber *stored = [state objectForKey:key];
          NSInteger active = stored ? [stored integerValue]
            : ScoreKeySignatureAlterationForStep (measure ? [measure keySignatureFifths] : 0, step);
          NSInteger displayed = active == [note accidental] ? NSIntegerMax : [note accidental];
          [result setObject:[NSNumber numberWithInteger:displayed]
                     forKey:[NSValue valueWithPointer:note]];
        }
      for (NSUInteger i = index; i < end; i++)
        {
          ScoreNote *note = [notes objectAtIndex:i];
          if ([note isRest]) continue;
          NSInteger octave = 0, step = DiatonicStepAndOctaveForNote (note, &octave);
          NSString *key = [NSString stringWithFormat:@"%ld:%ld:%ld", (long)[note track],
                                                   (long)step, (long)octave];
          [state setObject:[NSNumber numberWithInteger:[note accidental]] forKey:key];
        }
      index = end;
    }
  return result;
}

@implementation ScoreDocument

- (NSString *)title
{
  return _title;
}

- (void)setTitle:(NSString *)title
{
  if (_title != title)
    {
      [_title release];
      _title = [title retain];
    }
}

- (NSString *)titleFontName
{
  return _titleFontName;
}

- (void)setTitleFontName:(NSString *)fontName
{
  if (_titleFontName != fontName)
    {
      [_titleFontName release];
      _titleFontName = [fontName copy];
    }
}

- (NSString *)composer
{
  return _composer;
}

- (void)setComposer:(NSString *)composer
{
  if (_composer != composer)
    {
      [_composer release];
      _composer = [composer copy];
    }
}

- (NSMutableArray *)notes
{
  return _notes;
}

- (void)setNotes:(NSMutableArray *)notes
{
  if (_notes != notes)
    {
      [_notes release];
      _notes = [notes retain];
    }
}

- (NSMutableArray *)measures
{
  return _measures;
}

- (void)setMeasures:(NSMutableArray *)measures
{
  if (_measures != measures)
    {
      [_measures release];
      _measures = [measures retain];
    }
}

- (void)buildDefaultMeasures
{
  [_measures removeAllObjects];
  NSUInteger duration = (_ticksPerQuarter * 4 * _timeSignatureNumerator)
                        / MAX ((NSUInteger)1, _timeSignatureDenominator);
  if (duration == 0)
    duration = MAX ((NSUInteger)1, _ticksPerQuarter * 4);
  NSUInteger count = MAX ((NSUInteger)1, (_totalTicks + duration - 1) / duration);
  for (NSUInteger index = 0; index < count; index++)
    {
      ScoreMeasure *measure = [[[ScoreMeasure alloc] init] autorelease];
      [measure setNumber:(NSInteger)index + 1];
      [measure setStartTick:index * duration];
      [measure setDurationTicks:duration];
      [measure setTimeSignatureNumerator:_timeSignatureNumerator];
      [measure setTimeSignatureDenominator:_timeSignatureDenominator];
      [_measures addObject:measure];
    }
  for (ScoreNote *note in _notes)
    {
      ScoreMeasure *measure = [self measureContainingTick:[note startTick]];
      [note setMeasureIndex:measure ? (NSInteger)[_measures indexOfObjectIdenticalTo:measure] : -1];
    }
}

- (ScoreMeasure *)measureContainingTick:(NSUInteger)tick
{
  for (ScoreMeasure *measure in _measures)
    {
      NSUInteger end = [measure startTick] + [measure durationTicks];
      if (tick >= [measure startTick] && tick < end)
        return measure;
    }
  return nil;
}

- (ScoreMeasure *)ensureMeasureContainingTick:(NSUInteger)tick
{
  ScoreMeasure *existing = [self measureContainingTick:tick];
  if (existing)
    return existing;
  if ([_measures count] == 0)
    [self buildDefaultMeasures];
  existing = [self measureContainingTick:tick];
  while (!existing)
    {
      ScoreMeasure *previous = [_measures lastObject];
      NSUInteger start = previous ? [previous startTick] + [previous durationTicks] : 0;
      NSUInteger beats = previous ? [previous timeSignatureNumerator] : _timeSignatureNumerator;
      NSUInteger beatType
        = previous ? [previous timeSignatureDenominator] : _timeSignatureDenominator;
      NSUInteger duration = (_ticksPerQuarter * 4 * beats) / MAX ((NSUInteger)1, beatType);
      if (duration == 0)
        duration = MAX ((NSUInteger)1, _ticksPerQuarter * 4);
      ScoreMeasure *measure = [[[ScoreMeasure alloc] init] autorelease];
      [measure setNumber:previous ? [previous number] + 1 : 1];
      [measure setStartTick:start];
      [measure setDurationTicks:duration];
      [measure setTimeSignatureNumerator:beats];
      [measure setTimeSignatureDenominator:beatType];
      [_measures addObject:measure];
      if (tick >= start && tick < start + duration)
        existing = measure;
    }
  return existing;
}

- (NSMutableDictionary *)partNames
{
  return _partNames;
}

- (void)setPartNames:(NSMutableDictionary *)partNames
{
  if (_partNames != partNames)
    {
      [_partNames release];
      _partNames = [partNames retain];
    }
}

- (NSMutableDictionary *)trackPrograms
{
  return _trackPrograms;
}

- (void)setTrackPrograms:(NSMutableDictionary *)trackPrograms
{
  if (_trackPrograms != trackPrograms)
    {
      [_trackPrograms release];
      _trackPrograms = [trackPrograms retain];
    }
}

- (NSString *)annotationText
{
  return _annotationText;
}

- (void)setAnnotationText:(NSString *)annotationText
{
  if (_annotationText != annotationText)
    {
      [_annotationText release];
      _annotationText = [annotationText retain];
    }
}

- (NSUInteger)ticksPerQuarter
{
  return _ticksPerQuarter;
}

- (void)setTicksPerQuarter:(NSUInteger)ticksPerQuarter
{
  _ticksPerQuarter = ticksPerQuarter;
}

- (NSUInteger)tempoMicrosecondsPerQuarter
{
  return _tempoMicrosecondsPerQuarter;
}

- (void)setTempoMicrosecondsPerQuarter:(NSUInteger)tempoMicrosecondsPerQuarter
{
  _tempoMicrosecondsPerQuarter = tempoMicrosecondsPerQuarter;
  if ([_tempoEvents count] > 0)
    [[_tempoEvents objectAtIndex:0] setMicrosecondsPerQuarter:tempoMicrosecondsPerQuarter];
}

- (NSUInteger)timeSignatureNumerator
{
  return _timeSignatureNumerator;
}

- (void)setTimeSignatureNumerator:(NSUInteger)timeSignatureNumerator
{
  _timeSignatureNumerator = timeSignatureNumerator;
}

- (NSUInteger)timeSignatureDenominator
{
  return _timeSignatureDenominator;
}

- (void)setTimeSignatureDenominator:(NSUInteger)timeSignatureDenominator
{
  _timeSignatureDenominator = timeSignatureDenominator;
}

- (NSUInteger)totalTicks
{
  return _totalTicks;
}

- (void)setTotalTicks:(NSUInteger)totalTicks
{
  _totalTicks = totalTicks;
}

- (id)init
{
  self = [super init];
  if (self)
    {
      _notes = [[NSMutableArray alloc] init];
      _measures = [[NSMutableArray alloc] init];
      _partNames = [[NSMutableDictionary alloc] init];
      _trackPrograms = [[NSMutableDictionary alloc] init];
      _annotationText = [@"" retain];
      _titleFontName = [@"Times New Roman" copy];
      _ticksPerQuarter = 480;
      _tempoMicrosecondsPerQuarter = 500000;
      _timeSignatureNumerator = 4;
      _timeSignatureDenominator = 4;
      _totalTicks = 0;
      _parts = [[NSMutableArray alloc] init];
      _tempoEvents = [[NSMutableArray alloc] init];
      _midiRoutes = [[NSMutableArray alloc] init];
      _synthesisGraph = [[ScoreSynthesisGraph alloc] init];
      _compositionProgram = [[ScoreCompositionProgram alloc] init];
      _pageLayout = [[ScorePageLayout alloc] init];
    }
  return self;
}

- (void)dealloc
{
  [_title release];
  [_titleFontName release];
  [_composer release];
  [_notes release];
  [_measures release];
  [_partNames release];
  [_trackPrograms release];
  [_annotationText release];
  [_parts release];
  [_tempoEvents release];
  [_midiRoutes release];
  [_synthesisGraph release];
  [_compositionProgram release];
  [_pageLayout release];
  [super dealloc];
}

- (NSString *)nameForTrack:(NSInteger)track
{
  return [_partNames objectForKey:[NSNumber numberWithInteger:track]];
}

- (void)setName:(NSString *)name forTrack:(NSInteger)track
{
  NSString *trimmed =
    [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([trimmed length] == 0)
    {
      return;
    }
  [_partNames setObject:trimmed forKey:[NSNumber numberWithInteger:track]];
}

- (NSNumber *)programForTrack:(NSInteger)track
{
  return [_trackPrograms objectForKey:[NSNumber numberWithInteger:track]];
}

- (void)setProgram:(NSNumber *)program forTrack:(NSInteger)track
{
  NSNumber *trackNumber = [NSNumber numberWithInteger:track];
  if (!program)
    {
      [_trackPrograms removeObjectForKey:trackNumber];
      return;
    }

  NSInteger value = [program integerValue];
  if (value < 0 || value > 127)
    {
      [_trackPrograms removeObjectForKey:trackNumber];
      return;
    }
  [_trackPrograms setObject:[NSNumber numberWithInteger:value] forKey:trackNumber];
}

- (NSMutableArray *)parts
{
  return _parts;
}
- (void)setParts:(NSMutableArray *)parts
{
  if (_parts != parts)
    {
      [_parts release];
      _parts = [parts retain];
    }
}
- (NSMutableArray *)tempoEvents
{
  return _tempoEvents;
}
- (void)setTempoEvents:(NSMutableArray *)events
{
  if (_tempoEvents != events)
    {
      [_tempoEvents release];
      _tempoEvents = [events retain];
    }
}
- (NSMutableArray *)midiRoutes
{
  return _midiRoutes;
}
- (void)setMidiRoutes:(NSMutableArray *)routes
{
  if (_midiRoutes != routes)
    {
      [_midiRoutes release];
      _midiRoutes = [routes retain];
    }
}
- (ScoreSynthesisGraph *)synthesisGraph
{
  return _synthesisGraph;
}
- (void)setSynthesisGraph:(ScoreSynthesisGraph *)graph
{
  if (_synthesisGraph != graph)
    {
      [_synthesisGraph release];
      _synthesisGraph = [graph retain];
    }
}
- (ScoreCompositionProgram *)compositionProgram
{
  return _compositionProgram;
}
- (void)setCompositionProgram:(ScoreCompositionProgram *)program
{
  if (_compositionProgram != program)
    {
      [_compositionProgram release];
      _compositionProgram = [program retain];
    }
}
- (ScorePageLayout *)pageLayout
{
  return _pageLayout;
}
- (void)setPageLayout:(ScorePageLayout *)layout
{
  if (_pageLayout != layout)
    {
      [_pageLayout release];
      _pageLayout = [layout retain];
    }
}

- (void)rebuildStructuredPartsFromLegacyTracks
{
  NSMutableSet *trackSet = [NSMutableSet setWithArray:[_partNames allKeys]];
  [trackSet addObjectsFromArray:[_trackPrograms allKeys]];
  for (ScoreNote *note in _notes)
    [trackSet addObject:[NSNumber numberWithInteger:[note track]]];
  if ([trackSet count] == 0)
    [trackSet addObject:[NSNumber numberWithInteger:0]];
  NSArray *tracks = [[trackSet allObjects] sortedArrayUsingSelector:@selector (compare:)];
  [_parts removeAllObjects];
  [_midiRoutes removeAllObjects];
  for (NSNumber *trackNumber in tracks)
    {
      NSInteger track = [trackNumber integerValue];
      ScorePartDefinition *part = [[[ScorePartDefinition alloc] init] autorelease];
      [part setLegacyTrack:track];
      NSString *name = [self nameForTrack:track];
      [part
        setName:[name length] ? name : [NSString stringWithFormat:@"Part %ld", (long)(track + 1)]];
      [part setAbbreviatedName:[part name]];
      ScoreInstrumentDefinition *instrument =
        [[[ScoreInstrumentDefinition alloc] init] autorelease];
      [instrument setName:[part name]];
      [instrument setProgram:[[self programForTrack:track] integerValue]];
      [part setInstrument:instrument];

      NSInteger minimumPitch = 127, maximumPitch = 0;
      NSMutableSet *voiceNumbers = [NSMutableSet set];
      for (ScoreNote *note in _notes)
        if ([note track] == track && ![note isRest])
          {
            minimumPitch = MIN (minimumPitch, [note pitch]);
            maximumPitch = MAX (maximumPitch, [note pitch]);
            [voiceNumbers addObject:[NSNumber numberWithInteger:[note voice]]];
          }
      if ([voiceNumbers count] == 0)
        [voiceNumbers addObject:[NSNumber numberWithInteger:1]];
      BOOL grandStaff = minimumPitch < 55 && maximumPitch >= 67;
      NSUInteger staffCount = grandStaff ? 2 : 1;
      for (NSUInteger staffIndex = 0; staffIndex < staffCount; staffIndex++)
        {
          ScoreStaffDefinition *staff = [[[ScoreStaffDefinition alloc] init] autorelease];
          [staff setClef:(staffCount == 2 && staffIndex == 1) || maximumPitch < 60
                           ? ScoreStaffClefBass
                           : ScoreStaffClefTreble];
          for (NSNumber *voiceNumber in
               [[voiceNumbers allObjects] sortedArrayUsingSelector:@selector (compare:)])
            {
              ScoreVoiceDefinition *voice = [[[ScoreVoiceDefinition alloc] init] autorelease];
              [voice setNumber:[voiceNumber integerValue]];
              [voice setPreferredStemDirection:[voice number] == 1 ? 1 : -1];
              [[staff voices] addObject:voice];
            }
          [[part staves] addObject:staff];
        }
      [_parts addObject:part];
      ScoreMIDIRoute *route = [[[ScoreMIDIRoute alloc] init] autorelease];
      [route setSourceIdentifier:@"default-midi-input"];
      [route setSourceChannel:track % 16];
      [route setDestinationPartIdentifier:[part identifier]];
      [route setDestinationChannel:track % 16];
      [_midiRoutes addObject:route];
    }
  [_tempoEvents removeAllObjects];
  ScoreTempoEvent *tempo = [[[ScoreTempoEvent alloc] init] autorelease];
  [tempo setTick:0];
  [tempo setMicrosecondsPerQuarter:_tempoMicrosecondsPerQuarter];
  [_tempoEvents addObject:tempo];
}

- (void)copyMIDIRoutingAssignmentsFromDocument:(ScoreDocument *)document
{
  if (!document || document == self)
    return;

  NSMutableDictionary *sourcePartsByTrack = [NSMutableDictionary dictionary];
  for (ScorePartDefinition *part in [document parts])
    [sourcePartsByTrack setObject:part
                          forKey:[NSNumber numberWithInteger:[part legacyTrack]]];

  for (ScorePartDefinition *part in _parts)
    {
      ScorePartDefinition *source =
        [sourcePartsByTrack objectForKey:[NSNumber numberWithInteger:[part legacyTrack]]];
      if (!source)
        continue;
      [part setMidiOutputUniqueID:[source midiOutputUniqueID]];
      [part setMidiOutputName:[source midiOutputName]];
      [part setMidiFallbackMode:[source midiFallbackMode] ?: @"builtin"];
      [part setMidiFallbackUniqueID:[source midiFallbackUniqueID]];
      [part setMidiFallbackName:[source midiFallbackName]];
      [part setMuted:[source muted]];
      [part setSoloed:[source soloed]];
      [part setGain:[source gain]];
      [part setPan:[source pan]];
      [part setVisible:[source visible]];
      [part setGroupName:[source groupName]];
    }
}

- (NSUInteger)convertVoicesToPartsForTrack:(NSInteger)track
{
  NSMutableSet *voiceSet = [NSMutableSet set];
  for (ScoreNote *note in _notes)
    if ([note track] == track)
      [voiceSet addObject:[NSNumber numberWithInteger:[note voice]]];
  NSArray *voices = [[voiceSet allObjects] sortedArrayUsingSelector:@selector (compare:)];
  if ([voices count] < 2)
    return 0;

  NSInteger highestTrack = track;
  for (NSNumber *number in [_partNames allKeys])
    highestTrack = MAX (highestTrack, [number integerValue]);
  for (NSNumber *number in [_trackPrograms allKeys])
    highestTrack = MAX (highestTrack, [number integerValue]);
  for (ScoreNote *note in _notes)
    highestTrack = MAX (highestTrack, [note track]);

  NSString *baseName = [self nameForTrack:track];
  if (![baseName length])
    baseName = [NSString stringWithFormat:@"Part %ld", (long)(track + 1)];
  NSNumber *program = [self programForTrack:track];
  NSMutableDictionary *tracksByVoice = [NSMutableDictionary dictionary];
  for (NSUInteger index = 0; index < [voices count]; index++)
    {
      NSNumber *voice = [voices objectAtIndex:index];
      NSInteger destinationTrack = index == 0 ? track : ++highestTrack;
      [tracksByVoice setObject:[NSNumber numberWithInteger:destinationTrack] forKey:voice];
      [self setName:[NSString stringWithFormat:@"%@ — Voice %@", baseName, voice]
             forTrack:destinationTrack];
      [self setProgram:program ?: [NSNumber numberWithInteger:0] forTrack:destinationTrack];
    }
  for (ScoreNote *note in _notes)
    if ([note track] == track)
      {
        [note setTrack:[[tracksByVoice objectForKey:
                         [NSNumber numberWithInteger:[note voice]]] integerValue]];
        [note setVoice:1];
      }
  [self rebuildStructuredPartsFromLegacyTracks];
  return [voices count];
}

- (NSUInteger)convertPartsToVoices
{
  /* Only populated tracks can become notation voices.  Including an empty
   * named/programmed placeholder here creates a voice definition with no
   * notes and shifts the first audible part to voice 2. */
  NSMutableSet *trackSet = [NSMutableSet set];
  for (ScoreNote *note in _notes)
    [trackSet addObject:[NSNumber numberWithInteger:[note track]]];
  NSArray *tracks = [[trackSet allObjects] sortedArrayUsingSelector:@selector (compare:)];
  if ([tracks count] < 2)
    return 0;

  NSInteger destinationTrack = [[tracks objectAtIndex:0] integerValue];
  NSString *destinationName = [self nameForTrack:destinationTrack];
  NSNumber *destinationProgram = [self programForTrack:destinationTrack];
  NSMutableDictionary *voicesByTrack = [NSMutableDictionary dictionary];
  for (NSUInteger index = 0; index < [tracks count]; index++)
    [voicesByTrack setObject:[NSNumber numberWithUnsignedInteger:index + 1]
                      forKey:[tracks objectAtIndex:index]];
  for (ScoreNote *note in _notes)
    {
      [note setVoice:[[voicesByTrack objectForKey:
                       [NSNumber numberWithInteger:[note track]]] integerValue]];
      [note setTrack:destinationTrack];
    }
  [_partNames removeAllObjects];
  [_trackPrograms removeAllObjects];
  [self setName:[destinationName length] ? destinationName : @"Combined Parts"
         forTrack:destinationTrack];
  [self setProgram:destinationProgram ?: [NSNumber numberWithInteger:0]
          forTrack:destinationTrack];
  [self rebuildStructuredPartsFromLegacyTracks];
  return [tracks count];
}

- (id)copyWithZone:(NSZone *)zone
{
  ScoreDocument *copy = [[ScoreDocument allocWithZone:zone] init];
  [copy setTitle:_title];
  [copy setTitleFontName:_titleFontName];
  [copy setComposer:_composer];
  [copy setAnnotationText:_annotationText];
  [copy setTicksPerQuarter:_ticksPerQuarter];
  [copy setTempoMicrosecondsPerQuarter:_tempoMicrosecondsPerQuarter];
  [copy setTimeSignatureNumerator:_timeSignatureNumerator];
  [copy setTimeSignatureDenominator:_timeSignatureDenominator];
  [copy setTotalTicks:_totalTicks];
  NSMutableArray *notes = [NSMutableArray arrayWithCapacity:[_notes count]];
  for (ScoreNote *note in _notes)
    [notes addObject:[[note copy] autorelease]];
  [copy setNotes:notes];
  NSMutableArray *measures = [NSMutableArray arrayWithCapacity:[_measures count]];
  for (ScoreMeasure *measure in _measures)
    [measures addObject:[[measure copy] autorelease]];
  [copy setMeasures:measures];
  [copy setPartNames:[[[NSMutableDictionary alloc] initWithDictionary:_partNames
                                                            copyItems:YES] autorelease]];
  [copy setTrackPrograms:[[[NSMutableDictionary alloc] initWithDictionary:_trackPrograms
                                                                copyItems:YES] autorelease]];
  [copy setParts:[[[NSMutableArray alloc] initWithArray:_parts copyItems:YES] autorelease]];
  [copy setTempoEvents:[[[NSMutableArray alloc] initWithArray:_tempoEvents
                                                    copyItems:YES] autorelease]];
  [copy setMidiRoutes:[[[NSMutableArray alloc] initWithArray:_midiRoutes
                                                   copyItems:YES] autorelease]];
  [copy setSynthesisGraph:[[_synthesisGraph copy] autorelease]];
  [copy setCompositionProgram:[[_compositionProgram copy] autorelease]];
  [copy setPageLayout:[[_pageLayout copy] autorelease]];
  return copy;
}

@end
