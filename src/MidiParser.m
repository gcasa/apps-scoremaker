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

#import "MidiParser.h"
#import "MusicPlatformModel.h"
#import <stdint.h>
#import <math.h>

static NSString *const MidiParserErrorDomain = @"ScoreMakerMidiParser";

static uint16_t
ReadBE16 (const unsigned char *bytes, NSUInteger offset)
{
  return (uint16_t)((bytes[offset] << 8) | bytes[offset + 1]);
}

static uint32_t
ReadBE32 (const unsigned char *bytes, NSUInteger offset)
{
  return ((uint32_t)bytes[offset] << 24) | ((uint32_t)bytes[offset + 1] << 16)
         | ((uint32_t)bytes[offset + 2] << 8) | (uint32_t)bytes[offset + 3];
}

static BOOL
ReadVarLen (const unsigned char *bytes, NSUInteger length, NSUInteger *offset, NSUInteger *value)
{
  NSUInteger result = 0;
  NSUInteger count = 0;
  while (*offset < length && count < 4)
    {
      unsigned char c = bytes[(*offset)++];
      result = (result << 7) | (NSUInteger)(c & 0x7f);
      count++;
      if ((c & 0x80) == 0)
        {
          *value = result;
          return YES;
        }
    }
  return NO;
}

static NSError *
ParserError (NSString *message)
{
  NSDictionary *info = [NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
  return [NSError errorWithDomain:MidiParserErrorDomain code:1 userInfo:info];
}

static void
AppendByte (NSMutableData *data, unsigned char value)
{
  [data appendBytes:&value length:1];
}

static void
AppendBE16 (NSMutableData *data, uint16_t value)
{
  unsigned char bytes[] = { (unsigned char)((value >> 8) & 0xff), (unsigned char)(value & 0xff) };
  [data appendBytes:bytes length:2];
}

static void
AppendBE32 (NSMutableData *data, uint32_t value)
{
  unsigned char bytes[]
    = { (unsigned char)((value >> 24) & 0xff), (unsigned char)((value >> 16) & 0xff),
        (unsigned char)((value >> 8) & 0xff), (unsigned char)(value & 0xff) };
  [data appendBytes:bytes length:4];
}

static void
AppendVarLen (NSMutableData *data, NSUInteger value)
{
  unsigned char buffer[5];
  NSUInteger count = 0;
  buffer[count++] = (unsigned char)(value & 0x7f);
  while ((value >>= 7) > 0 && count < 5)
    {
      buffer[count++] = (unsigned char)((value & 0x7f) | 0x80);
    }
  while (count > 0)
    {
      AppendByte (data, buffer[--count]);
    }
}

static void
AppendMetaText (NSMutableData *data, unsigned char type, NSString *text)
{
  NSData *textData = [text dataUsingEncoding:NSUTF8StringEncoding];
  if (!textData)
    {
      textData = [text dataUsingEncoding:NSISOLatin1StringEncoding];
    }
  if (!textData)
    {
      return;
    }
  AppendByte (data, 0xff);
  AppendByte (data, type);
  AppendVarLen (data, [textData length]);
  [data appendData:textData];
}

static NSComparisonResult
CompareMidiEventDictionaries (id a, id b, void *context)
{
  (void)context;
  NSUInteger tickA = [[a objectForKey:@"tick"] unsignedIntegerValue];
  NSUInteger tickB = [[b objectForKey:@"tick"] unsignedIntegerValue];
  if (tickA < tickB)
    return NSOrderedAscending;
  if (tickA > tickB)
    return NSOrderedDescending;

  NSInteger orderA = [[a objectForKey:@"order"] integerValue];
  NSInteger orderB = [[b objectForKey:@"order"] integerValue];
  if (orderA < orderB)
    return NSOrderedAscending;
  if (orderA > orderB)
    return NSOrderedDescending;
  return NSOrderedSame;
}

static NSString *
MidiTextFromBytes (const unsigned char *bytes, NSUInteger length)
{
  NSData *data = [NSData dataWithBytes:bytes length:length];
  NSString *text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
  if (!text)
    {
      text = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    }
  return text;
}

static NSString *
GeneralMidiProgramName (unsigned char program)
{
  static NSString *names[] = { @"Acoustic Grand Piano",
                               @"Bright Acoustic Piano",
                               @"Electric Grand Piano",
                               @"Honky-tonk Piano",
                               @"Electric Piano 1",
                               @"Electric Piano 2",
                               @"Harpsichord",
                               @"Clavinet",
                               @"Celesta",
                               @"Glockenspiel",
                               @"Music Box",
                               @"Vibraphone",
                               @"Marimba",
                               @"Xylophone",
                               @"Tubular Bells",
                               @"Dulcimer",
                               @"Drawbar Organ",
                               @"Percussive Organ",
                               @"Rock Organ",
                               @"Church Organ",
                               @"Reed Organ",
                               @"Accordion",
                               @"Harmonica",
                               @"Tango Accordion",
                               @"Acoustic Guitar Nylon",
                               @"Acoustic Guitar Steel",
                               @"Electric Guitar Jazz",
                               @"Electric Guitar Clean",
                               @"Electric Guitar Muted",
                               @"Overdriven Guitar",
                               @"Distortion Guitar",
                               @"Guitar Harmonics",
                               @"Acoustic Bass",
                               @"Electric Bass Finger",
                               @"Electric Bass Pick",
                               @"Fretless Bass",
                               @"Slap Bass 1",
                               @"Slap Bass 2",
                               @"Synth Bass 1",
                               @"Synth Bass 2",
                               @"Violin",
                               @"Viola",
                               @"Cello",
                               @"Contrabass",
                               @"Tremolo Strings",
                               @"Pizzicato Strings",
                               @"Orchestral Harp",
                               @"Timpani",
                               @"String Ensemble 1",
                               @"String Ensemble 2",
                               @"Synth Strings 1",
                               @"Synth Strings 2",
                               @"Choir Aahs",
                               @"Voice Oohs",
                               @"Synth Voice",
                               @"Orchestra Hit",
                               @"Trumpet",
                               @"Trombone",
                               @"Tuba",
                               @"Muted Trumpet",
                               @"French Horn",
                               @"Brass Section",
                               @"Synth Brass 1",
                               @"Synth Brass 2",
                               @"Soprano Sax",
                               @"Alto Sax",
                               @"Tenor Sax",
                               @"Baritone Sax",
                               @"Oboe",
                               @"English Horn",
                               @"Bassoon",
                               @"Clarinet",
                               @"Piccolo",
                               @"Flute",
                               @"Recorder",
                               @"Pan Flute",
                               @"Blown Bottle",
                               @"Shakuhachi",
                               @"Whistle",
                               @"Ocarina",
                               @"Lead 1 Square",
                               @"Lead 2 Sawtooth",
                               @"Lead 3 Calliope",
                               @"Lead 4 Chiff",
                               @"Lead 5 Charang",
                               @"Lead 6 Voice",
                               @"Lead 7 Fifths",
                               @"Lead 8 Bass Lead",
                               @"Pad 1 New Age",
                               @"Pad 2 Warm",
                               @"Pad 3 Polysynth",
                               @"Pad 4 Choir",
                               @"Pad 5 Bowed",
                               @"Pad 6 Metallic",
                               @"Pad 7 Halo",
                               @"Pad 8 Sweep",
                               @"FX 1 Rain",
                               @"FX 2 Soundtrack",
                               @"FX 3 Crystal",
                               @"FX 4 Atmosphere",
                               @"FX 5 Brightness",
                               @"FX 6",
                               @"FX 7 Echoes",
                               @"FX 8 Sci-fi",
                               @"Sitar",
                               @"Banjo",
                               @"Shamisen",
                               @"Koto",
                               @"Kalimba",
                               @"Bag Pipe",
                               @"Fiddle",
                               @"Shanai",
                               @"Tinkle Bell",
                               @"Agogo",
                               @"Steel Drums",
                               @"Woodblock",
                               @"Taiko Drum",
                               @"Melodic Tom",
                               @"Synth Drum",
                               @"Reverse Cymbal",
                               @"Guitar Fret Noise",
                               @"Breath Noise",
                               @"Seashore",
                               @"Bird Tweet",
                               @"Telephone Ring",
                               @"Helicopter",
                               @"Applause",
                               @"Gunshot" };
  return names[MIN ((NSUInteger)program, (NSUInteger)127)];
}

@implementation MidiParser

+ (NSArray *)generalMidiProgramNames
{
  NSMutableArray *programs = [NSMutableArray arrayWithCapacity:128];
  for (NSUInteger program = 0; program < 128; program++)
    {
      [programs addObject:GeneralMidiProgramName ((unsigned char)program)];
    }
  return programs;
}

+ (NSArray *)instrumentDefinitionsFromINSFileAtPath:(NSString *)path error:(NSError **)error
{
  NSStringEncoding encoding = NSUTF8StringEncoding;
  NSString *contents = [NSString stringWithContentsOfFile:path usedEncoding:&encoding error:error];
  if (!contents)
    {
      contents = [NSString stringWithContentsOfFile:path
                                           encoding:NSISOLatin1StringEncoding
                                              error:error];
    }
  return contents ? [self instrumentDefinitionsFromINSString:contents error:error] : nil;
}

+ (NSArray *)instrumentDefinitionsFromINSString:(NSString *)contents error:(NSError **)error
{
  if (![contents length])
    {
      if (error) *error = ParserError (@"The instrument-definition file is empty.");
      return nil;
    }
  NSMutableDictionary *patchSections = [NSMutableDictionary dictionary];
  NSMutableArray *patchSectionOrder = [NSMutableArray array];
  NSMutableDictionary *instrumentSections = [NSMutableDictionary dictionary];
  NSMutableArray *instrumentOrder = [NSMutableArray array];
  NSString *area = nil;
  NSString *section = nil;
  NSArray *lines = [contents componentsSeparatedByCharactersInSet:
    [NSCharacterSet newlineCharacterSet]];
  for (NSString *rawLine in lines)
    {
      NSString *line = [rawLine stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if (![line length] || [line hasPrefix:@";"]) continue;
      if ([line hasPrefix:@"."])
        {
          area = [[line substringFromIndex:1] lowercaseString];
          section = nil;
          continue;
        }
      if ([line hasPrefix:@"["] && [line hasSuffix:@"]"] && [line length] > 2)
        {
          section = [line substringWithRange:NSMakeRange (1, [line length] - 2)];
          if ([area isEqualToString:@"patch names"])
            {
              if (![patchSections objectForKey:section])
                {
                  [patchSections setObject:[NSMutableDictionary dictionary] forKey:section];
                  [patchSectionOrder addObject:section];
                }
            }
          else if ([area isEqualToString:@"instrument definitions"])
            {
              if (![instrumentSections objectForKey:section])
                {
                  [instrumentSections setObject:[NSMutableDictionary dictionary] forKey:section];
                  [instrumentOrder addObject:section];
                }
            }
          continue;
        }
      NSRange equals = [line rangeOfString:@"="];
      if (!section || equals.location == NSNotFound) continue;
      NSString *key = [[line substringToIndex:equals.location]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
      NSString *value = [[line substringFromIndex:equals.location + 1]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
      if ([area isEqualToString:@"patch names"])
        {
          NSInteger program = [key integerValue];
          if (program >= 0 && program < 128 && [key length])
            [[patchSections objectForKey:section] setObject:value forKey:@(program)];
        }
      else if ([area isEqualToString:@"instrument definitions"]
               && [key hasPrefix:@"Patch["] && [key hasSuffix:@"]"])
        {
          NSString *bankText = [key substringWithRange:NSMakeRange (6, [key length] - 7)];
          [[instrumentSections objectForKey:section] setObject:value forKey:bankText];
        }
    }

  NSMutableArray *definitions = [NSMutableArray array];
  for (NSString *instrumentName in instrumentOrder)
    {
      NSDictionary *assignments = [instrumentSections objectForKey:instrumentName];
      NSMutableArray *banks = [NSMutableArray array];
      for (NSString *bankText in assignments)
        {
          NSString *patchSection = [assignments objectForKey:bankText];
          NSDictionary *patchesByNumber = [patchSections objectForKey:patchSection];
          if (!patchesByNumber) continue;
          NSInteger bank = [bankText isEqualToString:@"*"] ? 0 : [bankText integerValue];
          NSMutableArray *patches = [NSMutableArray arrayWithCapacity:128];
          for (NSInteger program = 0; program < 128; program++)
            [patches addObject:[patchesByNumber objectForKey:@(program)] ?: [NSNull null]];
          [banks addObject:@{ @"number" : @(MAX (0, MIN (16383, bank))),
                              @"name" : patchSection, @"patches" : patches }];
        }
      [banks sortUsingComparator:^NSComparisonResult (NSDictionary *left, NSDictionary *right) {
        return [[left objectForKey:@"number"] compare:[right objectForKey:@"number"]];
      }];
      if ([banks count])
        [definitions addObject:@{ @"name" : instrumentName, @"banks" : banks }];
    }
  /* Some useful .ins files contain only Patch Names. Expose each such section as a profile. */
  if (![definitions count])
    for (NSString *sectionName in patchSectionOrder)
      {
        NSDictionary *patchesByNumber = [patchSections objectForKey:sectionName];
        NSMutableArray *patches = [NSMutableArray arrayWithCapacity:128];
        for (NSInteger program = 0; program < 128; program++)
          [patches addObject:[patchesByNumber objectForKey:@(program)] ?: [NSNull null]];
        [definitions addObject:@{ @"name" : sectionName,
                                  @"banks" : @[ @{ @"number" : @0, @"name" : sectionName,
                                                    @"patches" : patches } ] }];
      }
  if (![definitions count])
    {
      if (error) *error = ParserError (@"No patch-name sections were found in the .ins file.");
      return nil;
    }
  return definitions;
}

+ (ScoreDocument *)parseFileAtPath:(NSString *)path error:(NSError **)error
{
  NSData *data = [NSData dataWithContentsOfFile:path];
  if (!data)
    {
      if (error)
        *error = ParserError (@"The MIDI file could not be read.");
      return nil;
    }

  const unsigned char *bytes = [data bytes];
  NSUInteger length = [data length];
  if (length < 14 || memcmp (bytes, "MThd", 4) != 0)
    {
      if (error)
        *error = ParserError (@"The file is not a Standard MIDI file.");
      return nil;
    }

  uint32_t headerLength = ReadBE32 (bytes, 4);
  if (headerLength < 6 || 8 + headerLength > length)
    {
      if (error)
        *error = ParserError (@"The MIDI header is truncated.");
      return nil;
    }

  uint16_t trackCount = ReadBE16 (bytes, 10);
  uint16_t division = ReadBE16 (bytes, 12);
  if (division & 0x8000)
    {
      if (error)
        *error = ParserError (@"SMPTE time-division MIDI files are not supported.");
      return nil;
    }

  ScoreDocument *document = [[[ScoreDocument alloc] init] autorelease];
  [document setTitle:[[path lastPathComponent] stringByDeletingPathExtension]];
  [document setTicksPerQuarter:division];
  NSMutableArray *keyEvents = [NSMutableArray array];

  NSUInteger offset = 8 + headerLength;
  for (NSUInteger trackIndex = 0; trackIndex < trackCount && offset + 8 <= length; trackIndex++)
    {
      if (memcmp (bytes + offset, "MTrk", 4) != 0)
        {
          if (error)
            *error = ParserError (@"A MIDI track chunk is missing or malformed.");
          return nil;
        }

      uint32_t trackLength = ReadBE32 (bytes, offset + 4);
      offset += 8;
      if (offset + trackLength > length)
        {
          if (error)
            *error = ParserError (@"A MIDI track chunk is truncated.");
          return nil;
        }

      [self parseTrackBytes:bytes + offset
                     length:trackLength
                 trackIndex:trackIndex
                   document:document];
      /* Key-signature meta events are collected separately because measures are
         constructed only after all MIDI tracks have been read. */
      NSUInteger scan = 0, tick = 0;
      unsigned char scanStatus = 0;
      const unsigned char *trackBytes = bytes + offset;
      while (scan < trackLength)
        {
          NSUInteger delta = 0;
          if (!ReadVarLen (trackBytes, trackLength, &scan, &delta)) break;
          tick += delta;
          if (scan >= trackLength) break;
          unsigned char status = trackBytes[scan++];
          if (status < 0x80) { if (!scanStatus) break; scan--; status = scanStatus; }
          else if (status < 0xf0) scanStatus = status;
          if (status == 0xff)
            {
              if (scan >= trackLength) break;
              unsigned char type = trackBytes[scan++];
              NSUInteger size = 0;
              if (!ReadVarLen (trackBytes, trackLength, &scan, &size) || scan + size > trackLength) break;
              if (type == 0x59 && size >= 2)
                [keyEvents addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                  [NSNumber numberWithUnsignedInteger:tick], @"tick",
                  [NSNumber numberWithInteger:(int8_t)trackBytes[scan]], @"fifths",
                  trackBytes[scan + 1] ? @"minor" : @"major", @"mode", nil]];
              scan += size; scanStatus = 0; continue;
            }
          if (status == 0xf0 || status == 0xf7)
            { NSUInteger size = 0; if (!ReadVarLen (trackBytes, trackLength, &scan, &size) || scan + size > trackLength) break; scan += size; scanStatus = 0; continue; }
          unsigned char kind = status & 0xf0;
          scan += (kind == 0xc0 || kind == 0xd0) ? 1 : 2;
        }
      offset += trackLength;
    }

  [[document notes] sortUsingSelector:@selector (compareScoreNote:)];
  [document buildDefaultMeasures];
  [keyEvents sortUsingFunction:CompareMidiEventDictionaries context:NULL];
  for (NSDictionary *event in keyEvents)
    {
      NSUInteger keyTick = [[event objectForKey:@"tick"] unsignedIntegerValue];
      ScoreMeasure *containing = [document measureContainingTick:keyTick];
      if (!containing || keyTick == [containing startTick])
        continue;
      NSUInteger index = [[document measures] indexOfObjectIdenticalTo:containing];
      NSUInteger oldEnd = [containing startTick] + [containing durationTicks];
      [containing setDurationTicks:keyTick - [containing startTick]];
      ScoreMeasure *split = [[containing copy] autorelease];
      [split setStartTick:keyTick];
      [split setDurationTicks:oldEnd - keyTick];
      [[document measures] insertObject:split atIndex:index + 1];
    }
  for (NSUInteger i = 0; i < [[document measures] count]; i++)
    [[[document measures] objectAtIndex:i] setNumber:(NSInteger)i + 1];
  NSInteger fifths = 0;
  NSString *mode = @"major";
  NSUInteger eventIndex = 0;
  for (ScoreMeasure *measure in [document measures])
    {
      while (eventIndex < [keyEvents count] &&
             [[[keyEvents objectAtIndex:eventIndex] objectForKey:@"tick"] unsignedIntegerValue]
               <= [measure startTick])
        {
          NSDictionary *event = [keyEvents objectAtIndex:eventIndex++];
          fifths = [[event objectForKey:@"fifths"] integerValue];
          mode = [event objectForKey:@"mode"];
        }
      [measure setKeySignatureFifths:fifths];
      [measure setKeyMode:mode];
    }
  for (ScoreNote *note in [document notes])
    {
      NSInteger pitchClass = (([note pitch] % 12) + 12) % 12;
      BOOL blackKey = pitchClass == 1 || pitchClass == 3 || pitchClass == 6 ||
                      pitchClass == 8 || pitchClass == 10;
      if (blackKey)
        {
          ScoreMeasure *measure = [document measureContainingTick:[note startTick]];
          NSInteger signature = measure ? [measure keySignatureFifths] : 0;
          if (signature)
            [note setAccidental:signature < 0 ? -1 : 1];
        }
      ScoreMeasure *measure = [document measureContainingTick:[note startTick]];
      [note setMeasureIndex:measure ? (NSInteger)[[document measures]
        indexOfObjectIdenticalTo:measure] : -1];
    }

  [document rebuildStructuredPartsFromLegacyTracks];
  return document;
}

+ (void)parseTrackBytes:(const unsigned char *)bytes
                 length:(NSUInteger)length
             trackIndex:(NSUInteger)trackIndex
               document:(ScoreDocument *)document
{
  NSMutableDictionary *activeNotes = [NSMutableDictionary dictionary];
  NSMutableDictionary *channelNames = [NSMutableDictionary dictionary];
  NSUInteger offset = 0;
  NSUInteger absoluteTick = 0;
  unsigned char runningStatus = 0;

  while (offset < length)
    {
      NSUInteger delta = 0;
      if (!ReadVarLen (bytes, length, &offset, &delta))
        {
          break;
        }
      absoluteTick += delta;
      if (absoluteTick > [document totalTicks])
        {
          [document setTotalTicks:absoluteTick];
        }
      if (offset >= length)
        {
          break;
        }

      unsigned char status = bytes[offset++];
      if (status < 0x80)
        {
          if (runningStatus == 0)
            {
              break;
            }
          offset--;
          status = runningStatus;
        }
      else if (status < 0xf0)
        {
          runningStatus = status;
        }

      if (status == 0xff)
        {
          if (offset >= length)
            break;
          unsigned char metaType = bytes[offset++];
          NSUInteger metaLength = 0;
          if (!ReadVarLen (bytes, length, &offset, &metaLength) || offset + metaLength > length)
            break;

          if (metaType == 0x03 || metaType == 0x04)
            {
              NSString *name = MidiTextFromBytes (bytes + offset, metaLength);
              if ([name length] > 0)
                {
                  [document setName:name forTrack:(NSInteger)trackIndex];
                }
            }
          else if (metaType == 0x51 && metaLength == 3)
            {
              [document setTempoMicrosecondsPerQuarter:((NSUInteger)bytes[offset] << 16)
                                                       | ((NSUInteger)bytes[offset + 1] << 8)
                                                       | (NSUInteger)bytes[offset + 2]];
            }
          else if (metaType == 0x58 && metaLength >= 2)
            {
              [document setTimeSignatureNumerator:bytes[offset]];
              [document setTimeSignatureDenominator:(NSUInteger)1 << bytes[offset + 1]];
            }

          offset += metaLength;
          runningStatus = 0;
          continue;
        }

      if (status == 0xf0 || status == 0xf7)
        {
          NSUInteger sysexLength = 0;
          if (!ReadVarLen (bytes, length, &offset, &sysexLength) || offset + sysexLength > length)
            break;
          offset += sysexLength;
          runningStatus = 0;
          continue;
        }

      unsigned char eventType = status & 0xf0;
      unsigned char channel = status & 0x0f;
      NSUInteger dataLength = (eventType == 0xc0 || eventType == 0xd0) ? 1 : 2;
      if (offset + dataLength > length)
        {
          break;
        }

      unsigned char data1 = bytes[offset++];
      unsigned char data2 = dataLength == 2 ? bytes[offset++] : 0;

      if (eventType == 0xc0)
        {
          NSString *name = channel == 9 ? @"Percussion" : GeneralMidiProgramName (data1);
          [channelNames setObject:name forKey:[NSNumber numberWithUnsignedChar:channel]];
          [document setProgram:[NSNumber numberWithUnsignedChar:data1]
                      forTrack:(NSInteger)trackIndex];
          if (![document nameForTrack:(NSInteger)trackIndex])
            {
              [document setName:name forTrack:(NSInteger)trackIndex];
            }
        }
      else if (eventType == 0x90 && data2 > 0)
        {
          NSString *key =
            [NSString stringWithFormat:@"%lu:%u:%u", (unsigned long)trackIndex, channel, data1];
          NSMutableArray *starts = [activeNotes objectForKey:key];
          if (!starts)
            {
              starts = [NSMutableArray array];
              [activeNotes setObject:starts forKey:key];
            }
          [starts
            addObject:[NSDictionary
                        dictionaryWithObjectsAndKeys:[NSNumber
                                                       numberWithUnsignedInteger:absoluteTick],
                                                     @"tick",
                                                     [NSNumber numberWithUnsignedChar:data2],
                                                     @"velocity", nil]];
        }
      else if (eventType == 0x80 || (eventType == 0x90 && data2 == 0))
        {
          NSString *key =
            [NSString stringWithFormat:@"%lu:%u:%u", (unsigned long)trackIndex, channel, data1];
          NSMutableArray *starts = [activeNotes objectForKey:key];
          if ([starts count] > 0)
            {
              NSDictionary *start = [starts objectAtIndex:0];
              NSUInteger startTick = [[start objectForKey:@"tick"] unsignedIntegerValue];
              [starts removeObjectAtIndex:0];
              if (absoluteTick > startTick)
                {
                  ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
                  [note setPitch:data1];
                  [note setChannel:channel];
                  [note setTrack:trackIndex];
                  [note setStartTick:startTick];
                  [note setDurationTicks:absoluteTick - startTick];
                  [note setVelocity:[[start objectForKey:@"velocity"] unsignedIntegerValue]];
                  if (![document nameForTrack:(NSInteger)trackIndex])
                    {
                      NSString *name =
                        [channelNames objectForKey:[NSNumber numberWithUnsignedChar:channel]];
                      if (!name && channel == 9)
                        {
                          name = @"Percussion";
                        }
                      if (name)
                        {
                          [document setName:name forTrack:(NSInteger)trackIndex];
                        }
                    }
                  [[document notes] addObject:note];
                }
            }
        }
    }
}

+ (NSData *)dataForDocument:(ScoreDocument *)document error:(NSError **)error
{
  if (!document)
    {
      if (error)
        *error = ParserError (@"There is no score to save.");
      return nil;
    }
  if ([document ticksPerQuarter] == 0 || [document ticksPerQuarter] > UINT16_MAX)
    {
      if (error)
        *error = ParserError (@"The score uses an unsupported MIDI time division.");
      return nil;
    }

  NSMutableArray *tracks = [NSMutableArray array];
  NSEnumerator *noteEnumerator = [[document notes] objectEnumerator];
  ScoreNote *note = nil;
  while ((note = [noteEnumerator nextObject]) != nil)
    {
      NSNumber *track = [NSNumber numberWithInteger:[note track]];
      if (![tracks containsObject:track])
        {
          [tracks addObject:track];
        }
    }
  NSEnumerator *definedTrackEnumerator = [[[document partNames] allKeys] objectEnumerator];
  NSNumber *definedTrack = nil;
  while ((definedTrack = [definedTrackEnumerator nextObject]) != nil)
    {
      if (![tracks containsObject:definedTrack])
        [tracks addObject:definedTrack];
    }
  definedTrackEnumerator = [[[document trackPrograms] allKeys] objectEnumerator];
  while ((definedTrack = [definedTrackEnumerator nextObject]) != nil)
    {
      if (![tracks containsObject:definedTrack])
        [tracks addObject:definedTrack];
    }
  if ([tracks count] == 0)
    {
      [tracks addObject:[NSNumber numberWithInteger:0]];
    }
  [tracks sortUsingSelector:@selector (compare:)];
  if ([tracks count] > UINT16_MAX)
    {
      if (error)
        *error = ParserError (@"The score has too many tracks for a Standard MIDI file.");
      return nil;
    }

  NSMutableData *file = [NSMutableData data];
  [file appendBytes:"MThd" length:4];
  AppendBE32 (file, 6);
  AppendBE16 (file, [tracks count] > 1 ? 1 : 0);
  AppendBE16 (file, (uint16_t)[tracks count]);
  AppendBE16 (file, (uint16_t)[document ticksPerQuarter]);

  NSEnumerator *trackEnumerator = [tracks objectEnumerator];
  NSNumber *trackNumber = nil;
  BOOL wroteGlobalMetadata = NO;
  while ((trackNumber = [trackEnumerator nextObject]) != nil)
    {
      NSInteger trackIndex = [trackNumber integerValue];
      NSMutableData *trackData = [NSMutableData data];

      BOOL globalTrack = !wroteGlobalMetadata;
      if (globalTrack)
        {
          AppendVarLen (trackData, 0);
          AppendByte (trackData, 0xff);
          AppendByte (trackData, 0x51);
          AppendByte (trackData, 3);
          NSUInteger tempo = [document tempoMicrosecondsPerQuarter] > 0
                               ? [document tempoMicrosecondsPerQuarter]
                               : 500000;
          AppendByte (trackData, (unsigned char)((tempo >> 16) & 0xff));
          AppendByte (trackData, (unsigned char)((tempo >> 8) & 0xff));
          AppendByte (trackData, (unsigned char)(tempo & 0xff));

          AppendVarLen (trackData, 0);
          AppendByte (trackData, 0xff);
          AppendByte (trackData, 0x58);
          AppendByte (trackData, 4);
          AppendByte (trackData,
                      (unsigned char)MIN ([document timeSignatureNumerator], (NSUInteger)255));
          NSUInteger denominator = MAX ([document timeSignatureDenominator], (NSUInteger)1);
          unsigned char denominatorPower = 0;
          while (denominator > 1 && denominatorPower < 7)
            {
              denominator >>= 1;
              denominatorPower++;
            }
          AppendByte (trackData, denominatorPower);
          AppendByte (trackData, 24);
          AppendByte (trackData, 8);
          wroteGlobalMetadata = YES;
        }

      NSString *trackName = [document nameForTrack:trackIndex];
      if ([trackName length] > 0)
        {
          AppendVarLen (trackData, 0);
          AppendMetaText (trackData, 0x03, trackName);
        }

      NSNumber *trackProgram = [document programForTrack:trackIndex];
      if (trackProgram)
        {
          unsigned char channel = 0;
          BOOL foundChannel = NO;
          noteEnumerator = [[document notes] objectEnumerator];
          while ((note = [noteEnumerator nextObject]) != nil)
            {
              if ([note track] == trackIndex && ![note isRest])
                {
                  channel = (unsigned char)MIN (MAX ([note channel], (NSInteger)0), (NSInteger)15);
                  foundChannel = YES;
                  break;
                }
            }
          if (!foundChannel)
            {
              channel = (unsigned char)MIN (MAX (trackIndex, (NSInteger)0), (NSInteger)15);
            }
          ScorePartDefinition *part = nil;
          for (ScorePartDefinition *candidate in [document parts])
            if ([candidate legacyTrack] == trackIndex) { part = candidate; break; }
          NSNumber *bankNumber = [[[part instrument] parameters] objectForKey:@"midiBankNumber"];
          if (bankNumber)
            {
              NSInteger bank = MAX ((NSInteger)0, MIN ((NSInteger)16383,
                                                       [bankNumber integerValue]));
              AppendVarLen (trackData, 0);
              AppendByte (trackData, (unsigned char)(0xb0 | channel));
              AppendByte (trackData, 0);
              AppendByte (trackData, (unsigned char)((bank >> 7) & 0x7f));
              AppendVarLen (trackData, 0);
              AppendByte (trackData, (unsigned char)(0xb0 | channel));
              AppendByte (trackData, 32);
              AppendByte (trackData, (unsigned char)(bank & 0x7f));
            }
          AppendVarLen (trackData, 0);
          AppendByte (trackData, (unsigned char)(0xc0 | channel));
          AppendByte (
            trackData,
            (unsigned char)MIN (MAX ([trackProgram integerValue], (NSInteger)0), (NSInteger)127));
        }

      NSMutableArray *events = [NSMutableArray array];
      if (globalTrack)
        {
          ScoreMeasure *previous = nil;
          for (ScoreMeasure *measure in [document measures])
            if (!previous || [previous keySignatureFifths] != [measure keySignatureFifths] ||
                ![[previous keyMode] isEqualToString:[measure keyMode]])
              {
                [events addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                  [NSNumber numberWithUnsignedInteger:[measure startTick]], @"tick", @-2, @"order",
                  @"key", @"kind", [NSNumber numberWithInteger:[measure keySignatureFifths]],
                  @"fifths", [measure keyMode], @"mode", nil]];
                previous = measure;
              }
        }
      noteEnumerator = [[document notes] objectEnumerator];
      while ((note = [noteEnumerator nextObject]) != nil)
        {
          if ([note track] != trackIndex)
            {
              continue;
            }
          if ([note isRest])
            {
              continue;
            }
          unsigned char pitch
            = (unsigned char)MIN (MAX ([note pitch], (NSInteger)0), (NSInteger)127);
          unsigned char channel
            = (unsigned char)MIN (MAX ([note channel], (NSInteger)0), (NSInteger)15);
          if ([note playbackFrequency] > 0.0 && channel != 9)
            {
              double equalFrequency = 440.0 * pow (2.0, ((double)[note pitch] - 69.0) / 12.0);
              double semitones = 12.0 * log ([note playbackFrequency] / equalFrequency) / log (2.0);
              /* General MIDI instruments conventionally use a +/-2-semitone bend range. */
              NSInteger bend = (NSInteger)llround (8192.0 + semitones * 4096.0);
              bend = MAX ((NSInteger)0, MIN ((NSInteger)16383, bend));
              [events addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                [NSNumber numberWithUnsignedInteger:[note startTick]], @"tick",
                [NSNumber numberWithInteger:1], @"order",
                [NSNumber numberWithUnsignedChar:(unsigned char)(0xe0 | channel)], @"status",
                [NSNumber numberWithUnsignedChar:(unsigned char)(bend & 0x7f)], @"data1",
                [NSNumber numberWithUnsignedChar:(unsigned char)((bend >> 7) & 0x7f)], @"data2",
                nil]];
            }
          [events
            addObject:[NSDictionary
                        dictionaryWithObjectsAndKeys:
                          [NSNumber numberWithUnsignedInteger:[note startTick]], @"tick",
                          [NSNumber numberWithInteger:2], @"order",
                          [NSNumber numberWithUnsignedChar:(unsigned char)(0x90 | channel)],
                          @"status", [NSNumber numberWithUnsignedChar:pitch], @"data1",
                          [NSNumber numberWithUnsignedInteger:[note velocity]], @"data2", nil]];
          [events addObject:[NSDictionary
                              dictionaryWithObjectsAndKeys:
                                [NSNumber numberWithUnsignedInteger:[note startTick]
                                                                    + MAX ([note durationTicks],
                                                                           (NSUInteger)1)],
                                @"tick", [NSNumber numberWithInteger:0], @"order",
                                [NSNumber numberWithUnsignedChar:(unsigned char)(0x80 | channel)],
                                @"status", [NSNumber numberWithUnsignedChar:pitch], @"data1",
                                [NSNumber numberWithUnsignedChar:64], @"data2", nil]];
        }
      [events sortUsingFunction:CompareMidiEventDictionaries context:NULL];

      NSUInteger previousTick = 0;
      NSEnumerator *eventEnumerator = [events objectEnumerator];
      NSDictionary *event = nil;
      while ((event = [eventEnumerator nextObject]) != nil)
        {
          NSUInteger tick = [[event objectForKey:@"tick"] unsignedIntegerValue];
          AppendVarLen (trackData, tick >= previousTick ? tick - previousTick : 0);
          if ([[event objectForKey:@"kind"] isEqualToString:@"key"])
            {
              AppendByte (trackData, 0xff); AppendByte (trackData, 0x59); AppendByte (trackData, 2);
              AppendByte (trackData, (unsigned char)(int8_t)[[event objectForKey:@"fifths"] integerValue]);
              AppendByte (trackData, [[event objectForKey:@"mode"] isEqualToString:@"minor"] ? 1 : 0);
              previousTick = tick;
              continue;
            }
          AppendByte (trackData, (unsigned char)[[event objectForKey:@"status"] unsignedCharValue]);
          AppendByte (trackData, (unsigned char)[[event objectForKey:@"data1"] unsignedCharValue]);
          AppendByte (trackData, (unsigned char)[[event objectForKey:@"data2"] unsignedCharValue]);
          previousTick = tick;
        }

      AppendVarLen (trackData, 0);
      AppendByte (trackData, 0xff);
      AppendByte (trackData, 0x2f);
      AppendByte (trackData, 0);

      [file appendBytes:"MTrk" length:4];
      AppendBE32 (file, (uint32_t)[trackData length]);
      [file appendData:trackData];
    }

  return file;
}

@end
