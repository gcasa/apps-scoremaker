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

#import "ScorefileParser.h"
#import <math.h>
#import <stdio.h>

static NSString *const ScorefileParserErrorDomain = @"ScoreMakerScorefileParser";
NSString *const ScorefileConsoleDidPrintNotification = @"ScorefileConsoleDidPrintNotification";
NSString *const ScorefileConsoleLineKey = @"ScorefileConsoleLine";
NSString *const ScorefileErrorRangeKey = @"ScorefileErrorRange";
NSString *const ScorefileErrorLineKey = @"ScorefileErrorLine";
NSString *const ScorefileErrorColumnKey = @"ScorefileErrorColumn";
static NSString *const ScoreMakerMetadataMarker = @"ScoreMaker Metadata V1";
static NSString *const ScoreMakerStructureMarker = @"ScoreMaker Structure V2";
static NSString *const ScorefileThreadDeadlineKey = @"ScoreMakerScorefileParserDeadline";
static NSMutableString *ScorefileConsoleOutput = nil;
static const NSUInteger ScorefileMaximumBytes = 32 * 1024 * 1024;
static const NSUInteger ScorefileMaximumIncludes = 128;
static const NSUInteger ScorefileMaximumIncludeDepth = 32;
static const NSUInteger ScorefileMaximumScriptNesting = 128;
static const NSUInteger ScorefileMaximumStatements = 250000;
static const NSUInteger ScorefileMaximumNotes = 250000;
static const NSTimeInterval ScorefileMaximumExecutionSeconds = 5.0;
static NSError *ScorefileError (NSString *message);

static void
ScorefileAppendConsoleLine (NSString *line)
{
  @synchronized ([ScorefileParser class])
  {
    if (!ScorefileConsoleOutput)
      ScorefileConsoleOutput = [[NSMutableString alloc] init];
    [ScorefileConsoleOutput appendString:line];
    [ScorefileConsoleOutput appendString:@"\n"];
  }
}

static BOOL
ScorefileDeadlineExceeded (NSTimeInterval deadline, NSError **error)
{
  if ([NSDate timeIntervalSinceReferenceDate] <= deadline)
    return NO;
  if (error)
    *error = ScorefileError (@"ScoreFile execution exceeded the 5-second parser budget.");
  return YES;
}

static NSError *
ScorefileError (NSString *message)
{
  NSDictionary *info = [NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
  return [NSError errorWithDomain:ScorefileParserErrorDomain code:1 userInfo:info];
}

static NSError *
ScorefileErrorAtRange (NSString *message, NSString *source, NSRange range)
{
  range.location = MIN (range.location, [source length]);
  range.length = MIN (range.length, [source length] - range.location);
  NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  while (range.length && [whitespace characterIsMember:[source characterAtIndex:range.location]])
    {
      range.location++;
      range.length--;
    }
  while (range.length &&
         [whitespace characterIsMember:[source characterAtIndex:NSMaxRange (range) - 1]])
    range.length--;
  NSUInteger line = 1;
  NSUInteger column = 1;
  for (NSUInteger i = 0; i < range.location; i++)
    {
      if ([source characterAtIndex:i] == '\n')
        {
          line++;
          column = 1;
        }
      else
        column++;
    }
  NSDictionary *info = [NSDictionary
    dictionaryWithObjectsAndKeys:message, NSLocalizedDescriptionKey, [NSValue valueWithRange:range],
                                 ScorefileErrorRangeKey, [NSNumber numberWithUnsignedInteger:line],
                                 ScorefileErrorLineKey, [NSNumber numberWithUnsignedInteger:column],
                                 ScorefileErrorColumnKey, nil];
  return [NSError errorWithDomain:ScorefileParserErrorDomain code:1 userInfo:info];
}

static NSError *
ScorefileLexicalError (NSString *source)
{
  BOOL inComment = NO;
  BOOL inQuote = NO;
  BOOL escaping = NO;
  NSUInteger constructStart = 0;
  for (NSUInteger i = 0; i < [source length]; i++)
    {
      unichar c = [source characterAtIndex:i];
      unichar next = i + 1 < [source length] ? [source characterAtIndex:i + 1] : 0;
      if (inComment)
        {
          if (c == '*' && next == '/')
            {
              inComment = NO;
              i++;
            }
          continue;
        }
      if (escaping)
        {
          escaping = NO;
          continue;
        }
      if (inQuote && c == '\\')
        {
          escaping = YES;
          continue;
        }
      if (!inQuote && c == '/' && next == '*')
        {
          inComment = YES;
          constructStart = i;
          i++;
          continue;
        }
      if (c == '"')
        {
          if (!inQuote)
            constructStart = i;
          inQuote = !inQuote;
        }
    }
  if (inComment)
    return ScorefileErrorAtRange (@"Unterminated block comment.", source,
                                  NSMakeRange (constructStart, [source length] - constructStart));
  if (inQuote)
    return ScorefileErrorAtRange (@"Unterminated quoted string.", source,
                                  NSMakeRange (constructStart, [source length] - constructStart));
  return nil;
}

static NSDictionary *
ScoreMakerJSONCommentFromScorefile (NSString *input, NSString *marker)
{
  NSRange markerRange = [input rangeOfString:marker];
  if (markerRange.location == NSNotFound)
    return nil;

  NSUInteger payloadStart = NSMaxRange (markerRange);
  NSRange searchRange = NSMakeRange (payloadStart, [input length] - payloadStart);
  NSRange commentEnd = [input rangeOfString:@"*/" options:0 range:searchRange];
  if (commentEnd.location == NSNotFound)
    return nil;

  NSString *encoded =
    [[input substringWithRange:NSMakeRange (payloadStart, commentEnd.location - payloadStart)]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSData *metadataData = [[[NSData alloc]
    initWithBase64EncodedString:encoded
                        options:NSDataBase64DecodingIgnoreUnknownCharacters] autorelease];
  if (!metadataData)
    return nil;

  id metadata = [NSJSONSerialization JSONObjectWithData:metadataData options:0 error:NULL];
  return [metadata isKindOfClass:[NSDictionary class]] ? metadata : nil;
}

static NSDictionary *
ScoreMakerMetadataFromScorefile (NSString *input)
{
  return ScoreMakerJSONCommentFromScorefile (input, ScoreMakerMetadataMarker);
}

static NSString *
ScoreMakerMetadataComment (ScoreDocument *document, NSError **error)
{
  NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
  if ([[document title] length] > 0)
    [metadata setObject:[document title] forKey:@"title"];
  if ([[document titleFontName] length] > 0)
    [metadata setObject:[document titleFontName] forKey:@"titleFont"];
  if ([[document composer] length] > 0)
    [metadata setObject:[document composer] forKey:@"composer"];
  if ([[document annotationText] length] > 0)
    [metadata setObject:[document annotationText] forKey:@"annotation"];
  if ([[document scorefileCompatibility] count] > 0)
    [metadata setObject:[document scorefileCompatibility] forKey:@"scorefileCompatibility"];
  [metadata setObject:[NSNumber numberWithInteger:1] forKey:@"version"];

  NSData *metadataData = [NSJSONSerialization dataWithJSONObject:metadata options:0 error:error];
  if (!metadataData)
    return nil;
  NSString *encoded =
    [metadataData base64EncodedStringWithOptions:NSDataBase64Encoding76CharacterLineLength];
  encoded = [encoded stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
  return [NSString stringWithFormat:@"/* %@\n%@\n*/\n\n", ScoreMakerMetadataMarker, encoded];
}

static NSString *
ScoreMakerStructureComment (ScoreDocument *document, NSError **error)
{
  NSMutableArray *measures = [NSMutableArray array];
  for (ScoreMeasure *measure in [document measures])
    {
      NSMutableDictionary *measureDetail = [NSMutableDictionary
        dictionaryWithObjectsAndKeys:
          [NSNumber numberWithInteger:[measure number]], @"number",
          [NSNumber numberWithUnsignedInteger:[measure startTick]], @"startTick",
          [NSNumber numberWithUnsignedInteger:[measure durationTicks]], @"durationTicks",
          [NSNumber numberWithUnsignedInteger:[measure timeSignatureNumerator]], @"beats",
          [NSNumber numberWithUnsignedInteger:[measure timeSignatureDenominator]], @"beatType",
          [NSNumber numberWithBool:[measure isImplicit]], @"implicit",
          [NSNumber numberWithInteger:[measure keySignatureFifths]], @"keyFifths",
          [measure keyMode], @"keyMode", [NSNumber numberWithBool:[measure repeatStart]],
          @"repeatStart", [NSNumber numberWithBool:[measure repeatEnd]], @"repeatEnd", nil];
      if ([[measure rehearsalMark] length])
        [measureDetail setObject:[measure rehearsalMark] forKey:@"rehearsalMark"];
      if ([[measure endingText] length])
        [measureDetail setObject:[measure endingText] forKey:@"endingText"];
      [measureDetail setObject:[NSNumber numberWithBool:[measure systemBreak]]
                        forKey:@"systemBreak"];
      [measureDetail setObject:[NSNumber numberWithBool:[measure pageBreak]] forKey:@"pageBreak"];
      [measures addObject:measureDetail];
    }
  NSMutableArray *noteDetails = [NSMutableArray array];
  for (ScoreNote *note in [document notes])
    {
      NSMutableDictionary *detail = [NSMutableDictionary
        dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:[note voice]], @"voice",
                                     [NSNumber numberWithInteger:[note measureIndex]],
                                     @"measureIndex",
                                     [NSNumber numberWithInteger:[note staffAssignment]],
                                     @"staffAssignment",
                                     [NSNumber numberWithUnsignedInteger:[note startTick]],
                                     @"startTick",
                                     [NSNumber numberWithUnsignedInteger:[note durationTicks]],
                                     @"durationTicks", [NSNumber numberWithInteger:[note pitch]],
                                     @"pitch", [NSNumber numberWithInteger:[note track]], @"track",
                                     [NSNumber numberWithBool:[note isRest]], @"rest",
                                     [NSNumber numberWithUnsignedInteger:[note velocity]],
                                     @"velocity", [NSNumber numberWithBool:[note tieStart]],
                                     @"tieStart", [NSNumber numberWithBool:[note tieEnd]],
                                     @"tieEnd",
                                     [NSNumber numberWithUnsignedInteger:[note tupletActual]],
                                     @"tupletActual",
                                     [NSNumber numberWithUnsignedInteger:[note tupletNormal]],
                                     @"tupletNormal", nil];
      if ([[note dynamic] length])
        [detail setObject:[note dynamic] forKey:@"dynamic"];
      if ([[note articulation] length])
        [detail setObject:[note articulation] forKey:@"articulation"];
      if ([[note lyric] length])
        [detail setObject:[note lyric] forKey:@"lyric"];
      if ([[note ornament] length])
        [detail setObject:[note ornament] forKey:@"ornament"];
      if ([note isGrace])
        [detail setObject:@YES forKey:@"grace"];
      if ([note isCue])
        [detail setObject:@YES forKey:@"cue"];
      if ([note tremoloStrokes])
        [detail setObject:@([note tremoloStrokes]) forKey:@"tremoloStrokes"];
      if ([[note hairpinStart] length])
        [detail setObject:[note hairpinStart] forKey:@"hairpinStart"];
      if ([note hairpinEnd])
        [detail setObject:@YES forKey:@"hairpinEnd"];
      if ([note pedalStart])
        [detail setObject:@YES forKey:@"pedalStart"];
      if ([note pedalEnd])
        [detail setObject:@YES forKey:@"pedalEnd"];
      if ([note octaveShiftStart])
        [detail setObject:@([note octaveShiftStart]) forKey:@"octaveShiftStart"];
      if ([note octaveShiftEnd])
        [detail setObject:@YES forKey:@"octaveShiftEnd"];
      if ([[note directionText] length])
        [detail setObject:[note directionText] forKey:@"directionText"];
      if ([[note provenance] length])
        [detail setObject:[note provenance] forKey:@"provenance"];
      [noteDetails addObject:detail];
    }
  NSDictionary *structure = [NSDictionary
    dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:2], @"version",
                                 [NSNumber numberWithUnsignedInteger:[document ticksPerQuarter]],
                                 @"ticksPerQuarter", measures, @"measures", noteDetails,
                                 @"noteDetails", nil];
  NSData *data = [NSJSONSerialization dataWithJSONObject:structure options:0 error:error];
  if (!data)
    return nil;
  NSString *encoded =
    [data base64EncodedStringWithOptions:NSDataBase64Encoding76CharacterLineLength];
  encoded = [encoded stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
  return [NSString stringWithFormat:@"/* %@\n%@\n*/\n\n", ScoreMakerStructureMarker, encoded];
}

static void
ApplyScoreMakerStructure (ScoreDocument *document, NSDictionary *structure)
{
  NSUInteger storedTPQ = [[structure objectForKey:@"ticksPerQuarter"] unsignedIntegerValue];
  storedTPQ = MAX ((NSUInteger)1, storedTPQ ?: [document ticksPerQuarter]);
  NSUInteger documentTPQ = MAX ((NSUInteger)1, [document ticksPerQuarter]);
  NSArray *storedMeasures = [structure objectForKey:@"measures"];
  if ([storedMeasures isKindOfClass:[NSArray class]] && [storedMeasures count] > 0)
    {
      NSMutableArray *measures = [NSMutableArray array];
      for (NSDictionary *item in storedMeasures)
        {
          if (![item isKindOfClass:[NSDictionary class]])
            continue;
          ScoreMeasure *measure = [[[ScoreMeasure alloc] init] autorelease];
          [measure setNumber:[[item objectForKey:@"number"] integerValue]];
          NSUInteger storedStart = [[item objectForKey:@"startTick"] unsignedIntegerValue];
          NSUInteger storedDuration = [[item objectForKey:@"durationTicks"] unsignedIntegerValue];
          [measure
            setStartTick:(NSUInteger)llround ((double)storedStart * documentTPQ / storedTPQ)];
          [measure
            setDurationTicks:MAX ((NSUInteger)1, (NSUInteger)llround ((double)storedDuration
                                                                      * documentTPQ / storedTPQ))];
          [measure setTimeSignatureNumerator:MAX ((NSUInteger)1, [[item objectForKey:@"beats"]
                                                                   unsignedIntegerValue])];
          [measure setTimeSignatureDenominator:MAX ((NSUInteger)1, [[item objectForKey:@"beatType"]
                                                                     unsignedIntegerValue])];
          [measure setImplicit:[[item objectForKey:@"implicit"] boolValue]];
          [measure setKeySignatureFifths:[[item objectForKey:@"keyFifths"] integerValue]];
          [measure setKeyMode:[item objectForKey:@"keyMode"]];
          [measure setRepeatStart:[[item objectForKey:@"repeatStart"] boolValue]];
          [measure setRepeatEnd:[[item objectForKey:@"repeatEnd"] boolValue]];
          [measure setRehearsalMark:[item objectForKey:@"rehearsalMark"]];
          [measure setEndingText:[item objectForKey:@"endingText"]];
          [measure setSystemBreak:[[item objectForKey:@"systemBreak"] boolValue]];
          [measure setPageBreak:[[item objectForKey:@"pageBreak"] boolValue]];
          [measures addObject:measure];
        }
      if ([measures count])
        [document setMeasures:measures];
    }
  NSArray *details = [structure objectForKey:@"noteDetails"];
  NSMutableDictionary *notesByIdentity = [NSMutableDictionary dictionary];
  NSMutableDictionary *nextNoteByIdentity = [NSMutableDictionary dictionary];
  for (ScoreNote *candidate in [document notes])
    {
      NSString *identity =
        [NSString stringWithFormat:@"%lu:%lu:%ld:%d", (unsigned long)[candidate startTick],
                                   (unsigned long)[candidate durationTicks],
                                   (long)[candidate pitch], [candidate isRest]];
      NSMutableArray *matches = [notesByIdentity objectForKey:identity];
      if (!matches)
        {
          matches = [NSMutableArray array];
          [notesByIdentity setObject:matches forKey:identity];
        }
      [matches addObject:candidate];
    }
  for (NSDictionary *item in details)
    {
      if (![item isKindOfClass:[NSDictionary class]])
        continue;
      NSUInteger storedStart = [[item objectForKey:@"startTick"] unsignedIntegerValue];
      NSUInteger storedDuration = [[item objectForKey:@"durationTicks"] unsignedIntegerValue];
      NSUInteger normalizedStart
        = (NSUInteger)llround ((double)storedStart * documentTPQ / storedTPQ);
      NSUInteger normalizedDuration
        = (NSUInteger)llround ((double)storedDuration * documentTPQ / storedTPQ);
      NSString *identity =
        [NSString stringWithFormat:@"%lu:%lu:%ld:%d", (unsigned long)normalizedStart,
                                   (unsigned long)normalizedDuration,
                                   (long)[[item objectForKey:@"pitch"] integerValue],
                                   [[item objectForKey:@"rest"] boolValue]];
      NSArray *matches = [notesByIdentity objectForKey:identity];
      NSUInteger matchIndex = [[nextNoteByIdentity objectForKey:identity] unsignedIntegerValue];
      if (matchIndex >= [matches count])
        continue;
      ScoreNote *note = [matches objectAtIndex:matchIndex];
      [nextNoteByIdentity setObject:[NSNumber numberWithUnsignedInteger:matchIndex + 1]
                             forKey:identity];
      [note setTrack:[[item objectForKey:@"track"] integerValue]];
      [note setVoice:[[item objectForKey:@"voice"] integerValue]];
      [note setMeasureIndex:[[item objectForKey:@"measureIndex"] integerValue]];
      [note setStaffAssignment:[[item objectForKey:@"staffAssignment"] integerValue]];
      NSNumber *velocity = [item objectForKey:@"velocity"];
      if (velocity)
        [note setVelocity:[velocity unsignedIntegerValue]];
      [note setTieStart:[[item objectForKey:@"tieStart"] boolValue]];
      [note setTieEnd:[[item objectForKey:@"tieEnd"] boolValue]];
      [note setTupletActual:[[item objectForKey:@"tupletActual"] unsignedIntegerValue]];
      [note setTupletNormal:[[item objectForKey:@"tupletNormal"] unsignedIntegerValue]];
      [note setDynamic:[item objectForKey:@"dynamic"]];
      [note setArticulation:[item objectForKey:@"articulation"]];
      [note setLyric:[item objectForKey:@"lyric"]];
      [note setOrnament:[item objectForKey:@"ornament"]];
      [note setGrace:[[item objectForKey:@"grace"] boolValue]];
      [note setCue:[[item objectForKey:@"cue"] boolValue]];
      [note setTremoloStrokes:[[item objectForKey:@"tremoloStrokes"] unsignedIntegerValue]];
      [note setHairpinStart:[item objectForKey:@"hairpinStart"]];
      [note setHairpinEnd:[[item objectForKey:@"hairpinEnd"] boolValue]];
      [note setPedalStart:[[item objectForKey:@"pedalStart"] boolValue]];
      [note setPedalEnd:[[item objectForKey:@"pedalEnd"] boolValue]];
      [note setOctaveShiftStart:[[item objectForKey:@"octaveShiftStart"] integerValue]];
      [note setOctaveShiftEnd:[[item objectForKey:@"octaveShiftEnd"] boolValue]];
      [note setDirectionText:[item objectForKey:@"directionText"]];
      [note setProvenance:[item objectForKey:@"provenance"]];
    }
  [[document notes] sortUsingSelector:@selector (compareScoreNote:)];
}

static NSString *
StripComments (NSString *input)
{
  NSMutableString *output = [NSMutableString string];
  NSUInteger length = [input length];
  BOOL inComment = NO;
  BOOL inQuote = NO;
  BOOL escaping = NO;
  for (NSUInteger i = 0; i < length; i++)
    {
      unichar c = [input characterAtIndex:i];
      unichar next = (i + 1 < length) ? [input characterAtIndex:i + 1] : 0;
      if (escaping)
        {
          [output appendFormat:@"%C", c];
          escaping = NO;
          continue;
        }
      if (!inComment && c == '\\')
        {
          [output appendFormat:@"%C", c];
          escaping = YES;
          continue;
        }
      if (!inComment && c == '"')
        {
          inQuote = !inQuote;
          [output appendFormat:@"%C", c];
          continue;
        }
      if (!inQuote && !inComment && c == '/' && next == '*')
        {
          inComment = YES;
          i++;
          continue;
        }
      if (!inQuote && inComment && c == '*' && next == '/')
        {
          inComment = NO;
          i++;
          continue;
        }
      if (!inComment)
        {
          [output appendFormat:@"%C", c];
        }
    }
  return output;
}

static NSArray *
ScorefileStatements (NSString *input)
{
  NSMutableArray *statements = [NSMutableArray array];
  NSMutableString *statement = [NSMutableString string];
  BOOL inQuote = NO;
  BOOL escaping = NO;

  for (NSUInteger i = 0; i < [input length]; i++)
    {
      unichar c = [input characterAtIndex:i];
      if (escaping)
        {
          [statement appendFormat:@"%C", c];
          escaping = NO;
          continue;
        }
      if (c == '\\')
        {
          [statement appendFormat:@"%C", c];
          escaping = YES;
          continue;
        }
      if (c == '"')
        {
          inQuote = !inQuote;
          [statement appendFormat:@"%C", c];
          continue;
        }
      if (c == ';' && !inQuote)
        {
          [statements addObject:[[statement copy] autorelease]];
          [statement setString:@""];
          continue;
        }
      [statement appendFormat:@"%C", c];
    }

  if ([statement length] > 0)
    {
      [statements addObject:[[statement copy] autorelease]];
    }
  return statements;
}

static NSUInteger
ScorefileOriginalIndexForCommentStrippedIndex (NSString *source, NSUInteger target)
{
  BOOL inQuote = NO, inComment = NO, escaping = NO;
  NSUInteger strippedIndex = 0;
  for (NSUInteger i = 0; i < [source length]; i++)
    {
      unichar c = [source characterAtIndex:i];
      unichar next = i + 1 < [source length] ? [source characterAtIndex:i + 1] : 0;
      if (inComment)
        {
          if (c == '*' && next == '/')
            {
              inComment = NO;
              i++;
            }
          continue;
        }
      if (escaping)
        {
          escaping = NO;
        }
      else if (inQuote && c == '\\')
        {
          escaping = YES;
        }
      else if (c == '"')
        {
          inQuote = !inQuote;
        }
      else if (!inQuote && c == '/' && next == '*')
        {
          inComment = YES;
          i++;
          continue;
        }
      if (strippedIndex == target)
        return i;
      strippedIndex++;
    }
  return [source length];
}

static NSArray *
ScorefileStatementRanges (NSString *input)
{
  NSMutableArray *ranges = [NSMutableArray array];
  BOOL inQuote = NO;
  BOOL inComment = NO;
  BOOL escaping = NO;
  NSUInteger start = 0;
  for (NSUInteger i = 0; i < [input length]; i++)
    {
      unichar c = [input characterAtIndex:i];
      unichar next = i + 1 < [input length] ? [input characterAtIndex:i + 1] : 0;
      if (inComment)
        {
          if (c == '*' && next == '/')
            {
              inComment = NO;
              i++;
            }
          continue;
        }
      if (escaping)
        {
          escaping = NO;
          continue;
        }
      if (c == '\\' && inQuote)
        {
          escaping = YES;
          continue;
        }
      if (!inQuote && c == '/' && next == '*')
        {
          inComment = YES;
          i++;
          continue;
        }
      if (c == '"')
        {
          inQuote = !inQuote;
          continue;
        }
      if (c == ';' && !inQuote)
        {
          [ranges addObject:[NSValue valueWithRange:NSMakeRange (start, i + 1 - start)]];
          start = i + 1;
        }
    }
  if (start < [input length])
    [ranges addObject:[NSValue valueWithRange:NSMakeRange (start, [input length] - start)]];
  return ranges;
}

static NSString *
Trim (NSString *input)
{
  return [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *
UnescapeScorefileString (NSString *input)
{
  NSMutableString *output = [NSMutableString string];
  BOOL escaping = NO;
  for (NSUInteger i = 0; i < [input length]; i++)
    {
      unichar c = [input characterAtIndex:i];
      if (escaping)
        {
          switch (c)
            {
            case 'n':
              [output appendString:@"\n"];
              break;
            case 'r':
              [output appendString:@"\r"];
              break;
            case ';':
              [output appendString:@";"];
              break;
            case '"':
              [output appendString:@"\""];
              break;
            case '\\':
              [output appendString:@"\\"];
              break;
            default:
              [output appendFormat:@"%C", c];
              break;
            }
          escaping = NO;
        }
      else if (c == '\\')
        {
          escaping = YES;
        }
      else
        {
          [output appendFormat:@"%C", c];
        }
    }
  if (escaping)
    {
      [output appendString:@"\\"];
    }
  return output;
}

static NSString *
EscapeScorefileString (NSString *input)
{
  NSString *escaped = [input stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
  escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
  escaped = [escaped stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
  return [escaped stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
}

static NSString *
QuotedStringValue (NSString *statement, NSString *prefix)
{
  if (![statement hasPrefix:prefix])
    {
      return nil;
    }
  NSString *value = Trim ([statement substringFromIndex:[prefix length]]);
  if ([value hasPrefix:@"\""] && [value hasSuffix:@"\""] && [value length] >= 2)
    {
      value = [value substringWithRange:NSMakeRange (1, [value length] - 2)];
    }
  return UnescapeScorefileString (value);
}

static NSString *
StringVariableValue (NSString *statement, NSString *name)
{
  NSString *prefix = [NSString stringWithFormat:@"string %@", name];
  if ([statement rangeOfString:prefix options:(NSCaseInsensitiveSearch | NSAnchoredSearch)].location
      == NSNotFound)
    return nil;
  NSRange equals = [statement rangeOfString:@"="];
  if (equals.location == NSNotFound)
    return nil;
  NSString *value = Trim ([statement substringFromIndex:NSMaxRange (equals)]);
  if (![value hasPrefix:@"\""] || ![value hasSuffix:@"\""] || [value length] < 2)
    return nil;
  return UnescapeScorefileString ([value substringWithRange:NSMakeRange (1, [value length] - 2)]);
}

typedef struct
{
  NSString *text;
  NSUInteger index;
  NSDictionary *variables;
  BOOL valid;
} ScorefileExpressionParser;

static void
SkipExpressionWhitespace (ScorefileExpressionParser *parser)
{
  NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  while (parser->index < [parser->text length] &&
         [whitespace characterIsMember:[parser->text characterAtIndex:parser->index]])
    {
      parser->index++;
    }
}

static double ParseScorefileExpression (ScorefileExpressionParser *parser);
static double EvaluateExpression (NSString *expression, NSDictionary *variables, BOOL *ok);

static NSString *const ScorefileRandomStateKey = @"__ScoreMakerRandomState";

static unsigned long long
ScorefileStableSeed (NSString *source)
{
  unsigned long long hash = 1469598103934665603ULL;
  BOOL quoted = NO, escaping = NO;
  for (NSUInteger i = 0; i < [source length]; i++)
    {
      unichar character = [source characterAtIndex:i];
      if (!quoted &&
          [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:character])
        continue;
      if (escaping)
        escaping = NO;
      else if (quoted && character == '\\')
        escaping = YES;
      else if (character == '"')
        quoted = !quoted;
      unsigned int value = character;
      hash ^= value & 0xffU;
      hash *= 1099511628211ULL;
      hash ^= value >> 8;
      hash *= 1099511628211ULL;
    }
  return hash ?: 0x9e3779b97f4a7c15ULL;
}

static void
SetScorefileVariable (NSMutableDictionary *variables, NSString *name, double value)
{
  [variables setObject:[NSNumber numberWithDouble:value] forKey:name];
  if ([name caseInsensitiveCompare:@"randomSeed"] == NSOrderedSame)
    {
      unsigned long long seed = (unsigned long long)llround (fabs (value));
      [variables setObject:[NSNumber numberWithUnsignedLongLong:seed ?: 0x9e3779b97f4a7c15ULL]
                    forKey:ScorefileRandomStateKey];
    }
}

static double
ScorefileNextRandom (NSDictionary *variables)
{
  unsigned long long state =
    [[variables objectForKey:ScorefileRandomStateKey] unsignedLongLongValue];
  if (!state)
    state = 0x9e3779b97f4a7c15ULL;
  state ^= state >> 12;
  state ^= state << 25;
  state ^= state >> 27;
  if ([variables isKindOfClass:[NSMutableDictionary class]])
    [(NSMutableDictionary *)variables setObject:[NSNumber numberWithUnsignedLongLong:state]
                                         forKey:ScorefileRandomStateKey];
  unsigned long long result = state * 2685821657736338717ULL;
  return (double)(result >> 11) * (1.0 / 9007199254740992.0);
}

static double
ParseScorefileFactor (ScorefileExpressionParser *parser)
{
  SkipExpressionWhitespace (parser);
  if (parser->index >= [parser->text length])
    {
      parser->valid = NO;
      return 0.0;
    }

  unichar c = [parser->text characterAtIndex:parser->index];
  if (c == '+' || c == '-')
    {
      parser->index++;
      double value = ParseScorefileFactor (parser);
      return c == '-' ? -value : value;
    }
  if (c == '(')
    {
      parser->index++;
      double value = ParseScorefileExpression (parser);
      SkipExpressionWhitespace (parser);
      if (parser->index >= [parser->text length] ||
          [parser->text characterAtIndex:parser->index] != ')')
        {
          parser->valid = NO;
          return 0.0;
        }
      parser->index++;
      return value;
    }

  NSUInteger start = parser->index;
  NSCharacterSet *identifierCharacters =
    [NSCharacterSet characterSetWithCharactersInString:
                      @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789."];
  while (parser->index < [parser->text length] &&
         [identifierCharacters characterIsMember:[parser->text characterAtIndex:parser->index]])
    {
      parser->index++;
    }
  if (parser->index == start)
    {
      parser->valid = NO;
      return 0.0;
    }

  NSString *token = [parser->text substringWithRange:NSMakeRange (start, parser->index - start)];
  SkipExpressionWhitespace (parser);
  if (parser->index < [parser->text length] && [parser->text characterAtIndex:parser->index] == '(')
    {
      parser->index++;
      NSMutableArray *arguments = [NSMutableArray array];
      SkipExpressionWhitespace (parser);
      while (parser->valid && parser->index < [parser->text length] &&
             [parser->text characterAtIndex:parser->index] != ')')
        {
          [arguments addObject:[NSNumber numberWithDouble:ParseScorefileExpression (parser)]];
          SkipExpressionWhitespace (parser);
          if (parser->index < [parser->text length] &&
              [parser->text characterAtIndex:parser->index] == ',')
            {
              parser->index++;
              continue;
            }
          break;
        }
      if (parser->index >= [parser->text length] ||
          [parser->text characterAtIndex:parser->index] != ')')
        {
          parser->valid = NO;
          return 0.0;
        }
      parser->index++;
      double a = [arguments count] ? [[arguments objectAtIndex:0] doubleValue] : 0.0;
      double b = [arguments count] > 1 ? [[arguments objectAtIndex:1] doubleValue] : 0.0;
      NSString *fn = [token lowercaseString];
      if ([fn isEqualToString:@"abs"] && [arguments count] == 1)
        return fabs (a);
      if ([fn isEqualToString:@"sqrt"] && [arguments count] == 1 && a >= 0)
        return sqrt (a);
      if ([fn isEqualToString:@"sin"] && [arguments count] == 1)
        return sin (a);
      if ([fn isEqualToString:@"cos"] && [arguments count] == 1)
        return cos (a);
      if ([fn isEqualToString:@"tan"] && [arguments count] == 1)
        return tan (a);
      if ([fn isEqualToString:@"log"] && [arguments count] == 1 && a > 0)
        return log (a);
      if ([fn isEqualToString:@"exp"] && [arguments count] == 1)
        return exp (a);
      if ([fn isEqualToString:@"floor"] && [arguments count] == 1)
        return floor (a);
      if ([fn isEqualToString:@"ceil"] && [arguments count] == 1)
        return ceil (a);
      if ([fn isEqualToString:@"min"] && [arguments count] == 2)
        return MIN (a, b);
      if ([fn isEqualToString:@"max"] && [arguments count] == 2)
        return MAX (a, b);
      if ([fn isEqualToString:@"pow"] && [arguments count] == 2)
        return pow (a, b);
      parser->valid = NO;
      return 0.0;
    }
  NSNumber *variable = [parser->variables objectForKey:token];
  if (variable)
    return [variable doubleValue];
  if ([[token lowercaseString] isEqualToString:@"ran"])
    return ScorefileNextRandom (parser->variables);

  NSScanner *scanner = [NSScanner scannerWithString:token];
  double value = 0.0;
  if (![scanner scanDouble:&value] || ![scanner isAtEnd])
    {
      parser->valid = NO;
      return 0.0;
    }
  return value;
}

static NSMutableDictionary *
ScorefileParameters (NSString *text)
{
  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  NSRegularExpression *regex =
    [NSRegularExpression regularExpressionWithPattern:@"(?:^|[,\\s])([A-Za-z_][A-Za-z0-9_]*)\\s*:"
                                              options:0
                                                error:NULL];
  NSArray *matches = [regex matchesInString:text options:0 range:NSMakeRange (0, [text length])];
  for (NSUInteger i = 0; i < [matches count]; i++)
    {
      NSTextCheckingResult *match = [matches objectAtIndex:i];
      NSString *name = [text substringWithRange:[match rangeAtIndex:1]];
      NSUInteger valueStart = NSMaxRange ([match range]);
      NSUInteger valueEnd
        = i + 1 < [matches count] ? [[matches objectAtIndex:i + 1] range].location : [text length];
      NSString *value
        = Trim ([text substringWithRange:NSMakeRange (valueStart, valueEnd - valueStart)]);
      while ([value hasSuffix:@","])
        value = Trim ([value substringToIndex:[value length] - 1]);
      [result setObject:value forKey:name];
    }
  return result;
}

static NSString *
ScorefileDictionaryValue (NSDictionary *dictionary, NSString *name)
{
  for (NSString *key in dictionary)
    if ([key caseInsensitiveCompare:name] == NSOrderedSame)
      return [dictionary objectForKey:key];
  return nil;
}

static double
ParseScorefilePower (ScorefileExpressionParser *parser)
{
  double value = ParseScorefileFactor (parser);
  SkipExpressionWhitespace (parser);
  if (parser->valid && parser->index < [parser->text length] &&
      [parser->text characterAtIndex:parser->index] == '^')
    {
      parser->index++;
      value = pow (value, ParseScorefilePower (parser));
    }
  return value;
}

static double
ParseScorefileTerm (ScorefileExpressionParser *parser)
{
  double value = ParseScorefilePower (parser);
  while (parser->valid)
    {
      SkipExpressionWhitespace (parser);
      if (parser->index >= [parser->text length])
        break;
      unichar operation = [parser->text characterAtIndex:parser->index];
      if (operation != '*' && operation != '/')
        break;
      parser->index++;
      double operand = ParseScorefilePower (parser);
      if (operation == '*')
        {
          value *= operand;
        }
      else if (operand != 0.0)
        {
          value /= operand;
        }
      else
        {
          parser->valid = NO;
        }
    }
  return value;
}

static NSRange
ScorefileTopLevelOperator (NSString *text, NSString *operation)
{
  NSInteger depth = 0;
  BOOL quoted = NO;
  for (NSUInteger i = 0; i + [operation length] <= [text length]; i++)
    {
      unichar c = [text characterAtIndex:i];
      if (c == '"')
        quoted = !quoted;
      if (quoted)
        continue;
      if (c == '(')
        depth++;
      else if (c == ')')
        depth--;
      if (depth == 0 &&
          [[text substringWithRange:NSMakeRange (i, [operation length])] isEqualToString:operation])
        return NSMakeRange (i, [operation length]);
    }
  return NSMakeRange (NSNotFound, 0);
}

static BOOL
EvaluateCondition (NSString *condition, NSDictionary *variables, BOOL *ok)
{
  NSString *text = Trim (condition);
  for (NSString *operation in [NSArray arrayWithObjects:@"||", @"&&", nil])
    {
      NSRange range = ScorefileTopLevelOperator (text, operation);
      if (range.location != NSNotFound)
        {
          BOOL leftOK = NO, rightOK = NO;
          BOOL left
            = EvaluateCondition ([text substringToIndex:range.location], variables, &leftOK);
          BOOL right
            = EvaluateCondition ([text substringFromIndex:NSMaxRange (range)], variables, &rightOK);
          if (ok)
            *ok = leftOK && rightOK;
          return [operation isEqualToString:@"&&"] ? left && right : left || right;
        }
    }
  for (NSString *operation in
       [NSArray arrayWithObjects:@"<=", @">=", @"==", @"!=", @"<", @">", nil])
    {
      NSRange range = ScorefileTopLevelOperator (text, operation);
      if (range.location == NSNotFound)
        continue;
      BOOL leftOK = NO, rightOK = NO;
      double left = EvaluateExpression ([text substringToIndex:range.location], variables, &leftOK);
      double right
        = EvaluateExpression ([text substringFromIndex:NSMaxRange (range)], variables, &rightOK);
      if (ok)
        *ok = leftOK && rightOK;
      if ([operation isEqualToString:@"<="])
        return left <= right;
      if ([operation isEqualToString:@">="])
        return left >= right;
      if ([operation isEqualToString:@"=="])
        return left == right;
      if ([operation isEqualToString:@"!="])
        return left != right;
      if ([operation isEqualToString:@"<"])
        return left < right;
      return left > right;
    }
  if ([text hasPrefix:@"!"])
    return !EvaluateCondition ([text substringFromIndex:1], variables, ok);
  BOOL expressionOK = NO;
  double value = EvaluateExpression (text, variables, &expressionOK);
  if (ok)
    *ok = expressionOK;
  return value != 0.0;
}

static double
ParseScorefileExpression (ScorefileExpressionParser *parser)
{
  double value = ParseScorefileTerm (parser);
  while (parser->valid)
    {
      SkipExpressionWhitespace (parser);
      if (parser->index >= [parser->text length])
        break;
      unichar operation = [parser->text characterAtIndex:parser->index];
      if (operation != '+' && operation != '-')
        break;
      parser->index++;
      double operand = ParseScorefileTerm (parser);
      value = operation == '+' ? value + operand : value - operand;
    }
  return value;
}

static double
EvaluateExpression (NSString *expression, NSDictionary *variables, BOOL *ok)
{
  ScorefileExpressionParser parser = { Trim (expression), 0, variables, YES };
  double value = ParseScorefileExpression (&parser);
  SkipExpressionWhitespace (&parser);
  if (parser.index != [parser.text length])
    parser.valid = NO;
  if (ok)
    *ok = parser.valid;
  return parser.valid ? value : 0.0;
}

static NSInteger
PitchForName (NSString *value, BOOL *ok)
{
  NSString *s = [[Trim (value) lowercaseString]
    stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@","]];
  if ([s hasSuffix:@"k"])
    {
      s = [s substringToIndex:[s length] - 1];
    }

  NSScanner *numberScanner = [NSScanner scannerWithString:s];
  NSInteger number = 0;
  if ([numberScanner scanInteger:&number])
    {
      if (ok)
        *ok = YES;
      return number;
    }

  if ([s length] < 2)
    {
      if (ok)
        *ok = NO;
      return 60;
    }

  unichar letter = [s characterAtIndex:0];
  NSInteger semitone = 0;
  switch (letter)
    {
    case 'c':
      semitone = 0;
      break;
    case 'd':
      semitone = 2;
      break;
    case 'e':
      semitone = 4;
      break;
    case 'f':
      semitone = 5;
      break;
    case 'g':
      semitone = 7;
      break;
    case 'a':
      semitone = 9;
      break;
    case 'b':
      semitone = 11;
      break;
    default:
      if (ok)
        *ok = NO;
      return 60;
    }

  NSUInteger octaveIndex = 1;
  if (octaveIndex < [s length])
    {
      unichar accidental = [s characterAtIndex:octaveIndex];
      if (accidental == 's' || accidental == '#')
        {
          semitone++;
          octaveIndex++;
        }
      else if (accidental == 'f')
        {
          semitone--;
          octaveIndex++;
        }
    }

  NSMutableString *octaveString = [NSMutableString string];
  while (octaveIndex < [s length])
    {
      unichar c = [s characterAtIndex:octaveIndex];
      if ((c >= '0' && c <= '9') || c == '-')
        {
          [octaveString appendFormat:@"%C", c];
          octaveIndex++;
        }
      else
        {
          break;
        }
    }

  if ([octaveString length] == 0)
    {
      if (ok)
        *ok = NO;
      return 60;
    }

  NSInteger octave = [octaveString integerValue];
  if (ok)
    *ok = YES;
  return (octave + 1) * 12 + semitone;
}

static NSInteger
AccidentalForName (NSString *value)
{
  NSString *s = [[Trim (value) lowercaseString]
    stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@","]];
  if ([s hasSuffix:@"k"])
    {
      s = [s substringToIndex:[s length] - 1];
    }
  if ([s length] < 2)
    {
      return 0;
    }
  unichar accidental = [s characterAtIndex:1];
  if (accidental == 's' || accidental == '#')
    return 1;
  if (accidental == 'f' || accidental == 'b')
    return -1;
  return 0;
}

static NSInteger
PitchForFrequency (NSString *value, NSDictionary *variables, BOOL *ok)
{
  BOOL expressionOK = NO;
  double frequency = EvaluateExpression (value, variables, &expressionOK);
  if (expressionOK && frequency > 0.0)
    {
      if (ok)
        *ok = YES;
      return (NSInteger)llround (69.0 + 12.0 * log (frequency / 440.0) / log (2.0));
    }

  return PitchForName (value, ok);
}

static NSString *
NoteNameForPitch (NSInteger pitch, NSInteger accidental)
{
  static NSString *sharpNames[]
    = { @"c", @"cs", @"d", @"ds", @"e", @"f", @"fs", @"g", @"gs", @"a", @"as", @"b" };
  static NSString *flatNames[]
    = { @"c", @"df", @"d", @"ef", @"e", @"f", @"gf", @"g", @"af", @"a", @"bf", @"b" };
  NSInteger pc = pitch % 12;
  if (pc < 0)
    pc += 12;
  NSInteger octave = (pitch / 12) - 1;
  NSString **names = accidental < 0 ? flatNames : sharpNames;
  return [NSString stringWithFormat:@"%@%ld", names[pc], (long)octave];
}

static BOOL
StringContains (NSString *haystack, NSString *needle)
{
  return [haystack rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL
StringHasPrefix (NSString *haystack, NSString *prefix)
{
  return
    [haystack rangeOfString:prefix options:(NSCaseInsensitiveSearch | NSAnchoredSearch)].location
    != NSNotFound;
}

static BOOL
IsPercussionDescriptor (NSString *value)
{
  NSString *s = Trim (value);
  return StringContains (s, @"percussion") || StringContains (s, @"drum");
}

static NSNumber *
GeneralMidiProgramForDescriptor (NSString *value)
{
  NSString *s = [Trim (value)
    stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"'"]];
  if ([s length] == 0)
    {
      return nil;
    }

  NSScanner *numberScanner = [NSScanner scannerWithString:s];
  NSInteger numericProgram = -1;
  if ([numberScanner scanInteger:&numericProgram] && [numberScanner isAtEnd])
    {
      if (numericProgram >= 0 && numericProgram <= 127)
        {
          return [NSNumber numberWithInteger:numericProgram];
        }
      if (numericProgram >= 1 && numericProgram <= 128)
        {
          return [NSNumber numberWithInteger:numericProgram - 1];
        }
    }

  if (StringContains (s, @"honky"))
    return [NSNumber numberWithInteger:3];
  if (StringContains (s, @"bright") && StringContains (s, @"piano"))
    return [NSNumber numberWithInteger:1];
  if ((StringContains (s, @"electric") || StringContains (s, @"rhodes"))
      && StringContains (s, @"piano"))
    return [NSNumber numberWithInteger:4];
  if (StringContains (s, @"harpsichord"))
    return [NSNumber numberWithInteger:6];
  if (StringContains (s, @"clav"))
    return [NSNumber numberWithInteger:7];
  if (StringContains (s, @"piano"))
    return [NSNumber numberWithInteger:0];

  if (StringContains (s, @"glockenspiel"))
    return [NSNumber numberWithInteger:9];
  if (StringContains (s, @"vibraphone"))
    return [NSNumber numberWithInteger:11];
  if (StringContains (s, @"marimba"))
    return [NSNumber numberWithInteger:12];
  if (StringContains (s, @"xylophone"))
    return [NSNumber numberWithInteger:13];
  if (StringContains (s, @"bells"))
    return [NSNumber numberWithInteger:14];

  if (StringContains (s, @"church") && StringContains (s, @"organ"))
    return [NSNumber numberWithInteger:19];
  if (StringContains (s, @"organ"))
    return [NSNumber numberWithInteger:16];
  if (StringContains (s, @"accordion"))
    return [NSNumber numberWithInteger:21];
  if (StringContains (s, @"harmonica"))
    return [NSNumber numberWithInteger:22];

  if (StringContains (s, @"nylon") && StringContains (s, @"guitar"))
    return [NSNumber numberWithInteger:24];
  if (StringContains (s, @"steel") && StringContains (s, @"guitar"))
    return [NSNumber numberWithInteger:25];
  if (StringContains (s, @"distortion") && StringContains (s, @"guitar"))
    return [NSNumber numberWithInteger:30];
  if (StringContains (s, @"overdriven") && StringContains (s, @"guitar"))
    return [NSNumber numberWithInteger:29];
  if (StringContains (s, @"electric") && StringContains (s, @"guitar"))
    return [NSNumber numberWithInteger:27];
  if (StringContains (s, @"pluck"))
    return [NSNumber numberWithInteger:24];
  if (StringContains (s, @"guitar"))
    return [NSNumber numberWithInteger:24];

  if (StringContains (s, @"contrabass") || StringContains (s, @"double bass"))
    return [NSNumber numberWithInteger:43];
  if (StringContains (s, @"electric") && StringContains (s, @"bass"))
    return [NSNumber numberWithInteger:33];
  if (StringContains (s, @"bass guitar"))
    return [NSNumber numberWithInteger:33];
  if (StringContains (s, @"fretless"))
    return [NSNumber numberWithInteger:35];
  if (StringContains (s, @"bassoon"))
    return [NSNumber numberWithInteger:70];
  if (StringContains (s, @"bass"))
    return [NSNumber numberWithInteger:32];

  if (StringContains (s, @"violin"))
    return [NSNumber numberWithInteger:40];
  if (StringContains (s, @"viola"))
    return [NSNumber numberWithInteger:41];
  if (StringContains (s, @"cello"))
    return [NSNumber numberWithInteger:42];
  if (StringContains (s, @"harp"))
    return [NSNumber numberWithInteger:46];
  if (StringContains (s, @"timpani"))
    return [NSNumber numberWithInteger:47];
  if (StringContains (s, @"pizzicato"))
    return [NSNumber numberWithInteger:45];
  if (StringContains (s, @"strings") || StringContains (s, @"string"))
    return [NSNumber numberWithInteger:48];

  if (StringContains (s, @"choir"))
    return [NSNumber numberWithInteger:52];
  if (StringContains (s, @"voice") || StringContains (s, @"vocal"))
    return [NSNumber numberWithInteger:53];

  if (StringContains (s, @"trumpet"))
    return [NSNumber numberWithInteger:56];
  if (StringContains (s, @"trombone"))
    return [NSNumber numberWithInteger:57];
  if (StringContains (s, @"tuba"))
    return [NSNumber numberWithInteger:58];
  if (StringContains (s, @"horn"))
    return [NSNumber numberWithInteger:60];
  if (StringContains (s, @"brass"))
    return [NSNumber numberWithInteger:61];

  if (StringContains (s, @"soprano sax"))
    return [NSNumber numberWithInteger:64];
  if (StringContains (s, @"alto sax"))
    return [NSNumber numberWithInteger:65];
  if (StringContains (s, @"tenor sax"))
    return [NSNumber numberWithInteger:66];
  if (StringContains (s, @"baritone sax"))
    return [NSNumber numberWithInteger:67];
  if (StringContains (s, @"sax"))
    return [NSNumber numberWithInteger:65];
  if (StringContains (s, @"oboe"))
    return [NSNumber numberWithInteger:68];
  if (StringContains (s, @"english horn"))
    return [NSNumber numberWithInteger:69];
  if (StringContains (s, @"clarinet"))
    return [NSNumber numberWithInteger:71];
  if (StringContains (s, @"piccolo"))
    return [NSNumber numberWithInteger:72];
  if (StringContains (s, @"flute"))
    return [NSNumber numberWithInteger:73];
  if (StringContains (s, @"recorder"))
    return [NSNumber numberWithInteger:74];

  return nil;
}

static NSString *
ScorefileParameterValue (NSString *params, NSString *name)
{
  NSString *prefix = [name stringByAppendingString:@":"];
  NSRange range = [params rangeOfString:prefix options:NSCaseInsensitiveSearch];
  if (range.location == NSNotFound)
    {
      return nil;
    }

  NSUInteger index = range.location + range.length;
  while (index < [params length] &&
         [[NSCharacterSet whitespaceAndNewlineCharacterSet]
           characterIsMember:[params characterAtIndex:index]])
    {
      index++;
    }
  if (index >= [params length])
    {
      return nil;
    }

  if ([params characterAtIndex:index] == '"')
    {
      NSMutableString *quoted = [NSMutableString string];
      BOOL escaping = NO;
      index++;
      while (index < [params length])
        {
          unichar c = [params characterAtIndex:index++];
          if (escaping)
            {
              [quoted appendFormat:@"%C", c];
              escaping = NO;
            }
          else if (c == '\\')
            {
              escaping = YES;
            }
          else if (c == '"')
            {
              break;
            }
          else
            {
              [quoted appendFormat:@"%C", c];
            }
        }
      return quoted;
    }

  NSCharacterSet *stopSet = [NSCharacterSet characterSetWithCharactersInString:@" ,;\t\r\n"];
  NSMutableString *value = [NSMutableString string];
  while (index < [params length])
    {
      unichar c = [params characterAtIndex:index];
      if ([stopSet characterIsMember:c])
        {
          break;
        }
      [value appendFormat:@"%C", c];
      index++;
    }
  return [value length] > 0 ? value : nil;
}

static NSString *
InstrumentDescriptorInParameters (NSString *params)
{
  NSArray *names = [NSArray arrayWithObjects:@"instrument", @"sound", @"synthPatch", @"patch",
                                             @"preset", @"program", @"gmProgram", nil];
  NSEnumerator *enumerator = [names objectEnumerator];
  NSString *name = nil;
  while ((name = [enumerator nextObject]) != nil)
    {
      NSString *value = ScorefileParameterValue (params, name);
      if ([value length] > 0)
        {
          return value;
        }
    }
  return nil;
}

static NSInteger
MidiChannelForScorefileTrack (NSInteger track, NSString *descriptor)
{
  if (descriptor && IsPercussionDescriptor (descriptor))
    {
      return 9;
    }
  NSInteger channel = track % 15;
  if (channel >= 9)
    {
      channel++;
    }
  return channel;
}

static NSString *
ScorefileIdentifierForPartName (NSString *name)
{
  NSMutableString *identifier = [NSMutableString string];
  NSCharacterSet *letters = [NSCharacterSet alphanumericCharacterSet];
  for (NSUInteger i = 0; i < [name length]; i++)
    {
      unichar c = [name characterAtIndex:i];
      if ([letters characterIsMember:c])
        {
          [identifier appendFormat:@"%C", c];
        }
      else if ([identifier length] > 0 && ![identifier hasSuffix:@"_"])
        {
          [identifier appendString:@"_"];
        }
    }
  if ([identifier length] == 0)
    {
      [identifier appendString:@"part"];
    }
  if ([[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[identifier characterAtIndex:0]])
    {
      [identifier insertString:@"part_" atIndex:0];
    }
  return identifier;
}

static NSUInteger
ScorefileMatchingDelimiter (NSString *source, NSUInteger opening, unichar open, unichar close)
{
  NSInteger depth = 0;
  BOOL quoted = NO, escaping = NO;
  for (NSUInteger i = opening; i < [source length]; i++)
    {
      unichar c = [source characterAtIndex:i];
      if (escaping)
        {
          escaping = NO;
          continue;
        }
      if (quoted && c == '\\')
        {
          escaping = YES;
          continue;
        }
      if (c == '"')
        {
          quoted = !quoted;
          continue;
        }
      if (quoted)
        continue;
      if (c == open)
        depth++;
      else if (c == close && --depth == 0)
        return i;
    }
  return NSNotFound;
}

static void
ScorefileSkipSpace (NSString *source, NSUInteger *index, NSUInteger end)
{
  NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  while (*index < end && [space characterIsMember:[source characterAtIndex:*index]])
    (*index)++;
}

static BOOL
ScorefileWordAt (NSString *source, NSUInteger index, NSUInteger end, NSString *word)
{
  if (index + [word length] > end ||
      [[source substringWithRange:NSMakeRange (index, [word length])] caseInsensitiveCompare:word]
        != NSOrderedSame)
    return NO;
  if (index + [word length] < end)
    {
      unichar next = [source characterAtIndex:index + [word length]];
      if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:next] || next == '_')
        return NO;
    }
  return YES;
}

static BOOL ExecuteScorefileScriptRange (NSString *, NSUInteger, NSUInteger, NSMutableDictionary *,
                                         NSMutableString *, NSUInteger *, NSUInteger, NSUInteger *,
                                         NSTimeInterval, NSError **);

static NSArray *
ScorefilePrintExpressions (NSString *text)
{
  NSMutableArray *expressions = [NSMutableArray array];
  NSUInteger start = 0, nesting = 0;
  BOOL quoted = NO, escaping = NO;
  for (NSUInteger index = 0; index < [text length]; index++)
    {
      unichar character = [text characterAtIndex:index];
      if (escaping)
        {
          escaping = NO;
          continue;
        }
      if (quoted && character == '\\')
        {
          escaping = YES;
          continue;
        }
      if (character == '"')
        {
          quoted = !quoted;
          continue;
        }
      if (quoted)
        continue;
      if (character == '(' || character == '[')
        nesting++;
      else if ((character == ')' || character == ']') && nesting > 0)
        nesting--;
      else if (character == ',' && nesting == 0)
        {
          [expressions
            addObject:Trim ([text substringWithRange:NSMakeRange (start, index - start)])];
          start = index + 1;
        }
    }
  [expressions addObject:Trim ([text substringFromIndex:start])];
  return expressions;
}

static BOOL
PrintScorefileExpressions (NSString *text, NSDictionary *environment)
{
  NSMutableString *line = [NSMutableString string];
  for (NSString *expression in ScorefilePrintExpressions (text))
    {
      if (![expression length])
        return NO;
      if ([expression hasPrefix:@"\""] && [expression hasSuffix:@"\""] && [expression length] >= 2)
        {
          [line appendString:UnescapeScorefileString ([expression
                               substringWithRange:NSMakeRange (1, [expression length] - 2)])];
          continue;
        }
      id variable = [environment objectForKey:expression];
      if ([variable isKindOfClass:[NSString class]])
        {
          [line appendString:variable];
          continue;
        }
      BOOL valueOK = NO;
      double value = EvaluateExpression (expression, environment, &valueOK);
      if (!valueOK)
        return NO;
      [line appendFormat:@"%.15g", value];
    }
  fprintf (stderr, "%s\n", [line UTF8String]);
  fflush (stderr);
  ScorefileAppendConsoleLine (line);
  [[NSNotificationCenter defaultCenter]
    postNotificationName:ScorefileConsoleDidPrintNotification
                  object:nil
                userInfo:[NSDictionary dictionaryWithObject:line forKey:ScorefileConsoleLineKey]];
  return YES;
}

static BOOL
ExecuteScorefileScriptRange (NSString *source, NSUInteger start, NSUInteger end,
                             NSMutableDictionary *environment, NSMutableString *output,
                             NSUInteger *steps, NSUInteger nesting, NSUInteger *statementCount,
                             NSTimeInterval deadline, NSError **error)
{
  if (nesting > ScorefileMaximumScriptNesting)
    {
      if (error)
        *error = ScorefileError (@"ScoreFile script nesting exceeds 128 blocks.");
      return NO;
    }
  NSUInteger index = start;
  while (index < end)
    {
      if (ScorefileDeadlineExceeded (deadline, error))
        return NO;
      ScorefileSkipSpace (source, &index, end);
      if (index >= end)
        break;
      BOOL isWhile = ScorefileWordAt (source, index, end, @"while");
      BOOL isIf = ScorefileWordAt (source, index, end, @"if");
      if (isWhile || isIf)
        {
          index += isWhile ? 5 : 2;
          ScorefileSkipSpace (source, &index, end);
          if (index >= end || [source characterAtIndex:index] != '(')
            goto malformed;
          NSUInteger conditionEnd = ScorefileMatchingDelimiter (source, index, '(', ')');
          if (conditionEnd == NSNotFound)
            goto malformed;
          NSString *condition =
            [source substringWithRange:NSMakeRange (index + 1, conditionEnd - index - 1)];
          index = conditionEnd + 1;
          ScorefileSkipSpace (source, &index, end);
          if (index >= end || [source characterAtIndex:index] != '{')
            goto malformed;
          NSUInteger blockEnd = ScorefileMatchingDelimiter (source, index, '{', '}');
          if (blockEnd == NSNotFound)
            goto malformed;
          NSUInteger bodyStart = index + 1, bodyEnd = blockEnd;
          index = blockEnd + 1;
          if (isWhile)
            {
              while (YES)
                {
                  BOOL conditionOK = NO;
                  BOOL result = EvaluateCondition (condition, environment, &conditionOK);
                  if (!conditionOK)
                    goto malformed;
                  if (!result)
                    break;
                  if (++(*steps) > 10000)
                    {
                      if (error)
                        *error = ScorefileErrorAtRange (
                          @"ScoreFile execution limit exceeded (10,000 loop iterations).", source,
                          NSMakeRange (MIN (index, [source length]), 0));
                      return NO;
                    }
                  if (!ExecuteScorefileScriptRange (source, bodyStart, bodyEnd, environment, output,
                                                    steps, nesting + 1, statementCount, deadline,
                                                    error))
                    return NO;
                }
            }
          else
            {
              BOOL conditionOK = NO;
              BOOL result = EvaluateCondition (condition, environment, &conditionOK);
              if (!conditionOK)
                goto malformed;
              NSUInteger elseStart = NSNotFound, elseEnd = NSNotFound;
              NSUInteger probe = index;
              ScorefileSkipSpace (source, &probe, end);
              if (ScorefileWordAt (source, probe, end, @"else"))
                {
                  probe += 4;
                  ScorefileSkipSpace (source, &probe, end);
                  if (probe >= end || [source characterAtIndex:probe] != '{')
                    goto malformed;
                  elseEnd = ScorefileMatchingDelimiter (source, probe, '{', '}');
                  if (elseEnd == NSNotFound)
                    goto malformed;
                  elseStart = probe + 1;
                  index = elseEnd + 1;
                }
              if (result)
                {
                  if (!ExecuteScorefileScriptRange (source, bodyStart, bodyEnd, environment, output,
                                                    steps, nesting + 1, statementCount, deadline,
                                                    error))
                    return NO;
                }
              else if (elseStart != NSNotFound)
                {
                  if (!ExecuteScorefileScriptRange (source, elseStart, elseEnd, environment, output,
                                                    steps, nesting + 1, statementCount, deadline,
                                                    error))
                    return NO;
                }
            }
          continue;
        }

      NSUInteger statementStart = index;
      BOOL quoted = NO;
      while (index < end)
        {
          unichar c = [source characterAtIndex:index++];
          if (c == '"')
            quoted = !quoted;
          if (c == ';' && !quoted)
            break;
        }
      NSString *statement = Trim ([source
        substringWithRange:NSMakeRange (
                             statementStart,
                             index - statementStart
                               - ((index && [source characterAtIndex:index - 1] == ';') ? 1 : 0))]);
      if (![statement length])
        continue;
      if (++(*statementCount) > ScorefileMaximumStatements)
        {
          if (error)
            *error = ScorefileError (@"ScoreFile generates more than 250,000 statements.");
          return NO;
        }
      if (ScorefileWordAt (statement, 0, [statement length], @"print"))
        {
          NSString *expressions = Trim ([statement substringFromIndex:5]);
          if (![expressions length] || !PrintScorefileExpressions (expressions, environment))
            goto malformed;
          [output appendFormat:@"/*__SM_TRACE:%lu:%lu*/%@;\n", (unsigned long)statementStart,
                               (unsigned long)(index - statementStart), statement];
          continue;
        }
      NSRegularExpression *stringDeclaration = [NSRegularExpression
        regularExpressionWithPattern:
          @"^string\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*=\\s*(\"(?:\\\\.|[^\"])*\")$"
                             options:NSRegularExpressionCaseInsensitive
                               error:NULL];
      NSTextCheckingResult *stringMatch =
        [stringDeclaration firstMatchInString:statement
                                      options:0
                                        range:NSMakeRange (0, [statement length])];
      if (stringMatch)
        {
          NSString *name = [statement substringWithRange:[stringMatch rangeAtIndex:1]];
          NSString *literal = [statement substringWithRange:[stringMatch rangeAtIndex:2]];
          NSString *value = UnescapeScorefileString (
            [literal substringWithRange:NSMakeRange (1, [literal length] - 2)]);
          [environment setObject:value forKey:name];
          [output appendFormat:@"/*__SM_TRACE:%lu:%lu*/%@;\n", (unsigned long)statementStart,
                               (unsigned long)(index - statementStart), statement];
          continue;
        }
      NSRegularExpression *declaration =
        [NSRegularExpression regularExpressionWithPattern:
                               @"^(?:int|double|var)\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*(?:=\\s*(.+))?$"
                                                  options:NSRegularExpressionCaseInsensitive
                                                    error:NULL];
      NSTextCheckingResult *match =
        [declaration firstMatchInString:statement
                                options:0
                                  range:NSMakeRange (0, [statement length])];
      NSRegularExpression *assignment =
        [NSRegularExpression regularExpressionWithPattern:@"^([A-Za-z_][A-Za-z0-9_]*)\\s*=\\s*(.+)$"
                                                  options:0
                                                    error:NULL];
      if (!match)
        match = [assignment firstMatchInString:statement
                                       options:0
                                         range:NSMakeRange (0, [statement length])];
      if (match)
        {
          NSString *name = [statement substringWithRange:[match rangeAtIndex:1]];
          NSString *expression = [match rangeAtIndex:2].location == NSNotFound
                                   ? @"0"
                                   : [statement substringWithRange:[match rangeAtIndex:2]];
          BOOL valueOK = NO;
          double value = EvaluateExpression (expression, environment, &valueOK);
          if (!valueOK)
            goto malformed;
          SetScorefileVariable (environment, name, value);
          [output appendFormat:@"/*__SM_TRACE:%lu:%lu*/var %@ = %.17g;\n",
                               (unsigned long)statementStart,
                               (unsigned long)(index - statementStart), name, value];
        }
      else
        [output appendFormat:@"/*__SM_TRACE:%lu:%lu*/%@;\n", (unsigned long)statementStart,
                             (unsigned long)(index - statementStart), statement];
      if ([output lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > ScorefileMaximumBytes)
        {
          if (error)
            *error = ScorefileError (@"Expanded ScoreFile exceeds the 32 MiB byte budget.");
          return NO;
        }
    }
  return YES;

malformed:
  if (error)
    *error = ScorefileErrorAtRange (@"Invalid ScoreFile script statement or expression.", source,
                                    NSMakeRange (MIN (index, [source length]), 0));
  return NO;
}

static NSString *
ExpandScorefileScript (NSString *source, NSMutableDictionary *environment, NSTimeInterval deadline,
                       NSError **error)
{
  NSMutableString *output = [NSMutableString string];
  NSUInteger steps = 0, statementCount = 0;
  return ExecuteScorefileScriptRange (source, 0, [source length], environment, output, &steps, 0,
                                      &statementCount, deadline, error)
           ? output
           : nil;
}

static NSDictionary *
ScorefileNamedNumericObject (NSString *declaration, NSString *kind)
{
  NSString *pattern = [NSString stringWithFormat:@"(?i)^%@\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*=", kind];
  NSRegularExpression *nameRegex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                             options:0
                                                                               error:NULL];
  NSTextCheckingResult *nameMatch =
    [nameRegex firstMatchInString:declaration
                          options:0
                            range:NSMakeRange (0, [declaration length])];
  if (!nameMatch)
    return nil;
  NSString *name = [declaration substringWithRange:[nameMatch rangeAtIndex:1]];
  NSRegularExpression *numberRegex = [NSRegularExpression
    regularExpressionWithPattern:@"[-+]?(?:[0-9]*\\.)?[0-9]+(?:[eE][-+]?[0-9]+)?"
                         options:0
                           error:NULL];
  NSMutableArray *numbers = [NSMutableArray array];
  for (NSTextCheckingResult *match in
       [numberRegex matchesInString:declaration
                            options:0
                              range:NSMakeRange (0, [declaration length])])
    [numbers addObject:@([[declaration substringWithRange:[match range]] doubleValue])];
  return [NSDictionary
    dictionaryWithObjectsAndKeys:name, @"name", numbers, @"values",
                                 @([declaration rangeOfString:@"|"].location != NSNotFound),
                                 @"hasSustainPoint", declaration, @"source", nil];
}

@implementation ScorefileParser

+ (NSString *)consoleOutput
{
  @synchronized (self)
  {
    return [[ScorefileConsoleOutput copy] autorelease] ?: @"";
  }
}

+ (void)clearConsoleOutput
{
  @synchronized (self)
  {
    [ScorefileConsoleOutput setString:@""];
  }
}

+ (NSString *)expandedSourceAtPath:(NSString *)path
                            budget:(NSMutableDictionary *)budget
                             depth:(NSUInteger)depth
                            active:(NSMutableArray *)active
                             error:(NSError **)error
{
  NSString *canonical = [path stringByStandardizingPath];
  if (depth > ScorefileMaximumIncludeDepth)
    {
      if (error)
        *error = ScorefileError (@"ScoreFile include nesting exceeds 32 files.");
      return nil;
    }
  NSUInteger includeCount = [[budget objectForKey:@"includes"] unsignedIntegerValue];
  if (depth > 0 && ++includeCount > ScorefileMaximumIncludes)
    {
      if (error)
        *error = ScorefileError (@"ScoreFile uses more than 128 include directives.");
      return nil;
    }
  [budget setObject:@(includeCount) forKey:@"includes"];
  if ([active containsObject:canonical])
    {
      NSArray *cycle = [[active arrayByAddingObject:canonical] valueForKey:@"lastPathComponent"];
      if (error)
        *error
          = ScorefileError ([NSString stringWithFormat:@"ScoreFile include cycle: %@.",
                                                       [cycle componentsJoinedByString:@" → "]]);
      return nil;
    }
  if (ScorefileDeadlineExceeded ([[budget objectForKey:@"deadline"] doubleValue], error))
    return nil;

  NSData *data = [NSData dataWithContentsOfFile:canonical
                                        options:NSDataReadingMappedIfSafe
                                          error:error];
  NSUInteger byteCount = [[budget objectForKey:@"bytes"] unsignedIntegerValue] + [data length];
  if (!data || byteCount > ScorefileMaximumBytes)
    {
      if (data && error)
        *error = ScorefileError (@"ScoreFile source and includes exceed the 32 MiB byte budget.");
      return nil;
    }
  [budget setObject:@(byteCount) forKey:@"bytes"];
  NSString *source = [[[NSString alloc] initWithData:data
                                            encoding:NSUTF8StringEncoding] autorelease];
  if (!source)
    source = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
  if (!source)
    {
      if (error)
        *error = ScorefileError (@"An included ScoreFile is not valid text.");
      return nil;
    }
  [active addObject:canonical];
  NSRegularExpression *include = [NSRegularExpression
    regularExpressionWithPattern:@"(?m)^\\s*(?:#include|include)\\s+\"([^\"]+)\"\\s*;?\\s*$"
                         options:0
                           error:NULL];
  NSMutableString *expanded = [NSMutableString string];
  NSString *encodedPath =
    [[canonical dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
  [expanded appendFormat:@"__scoremakerSourceFile \"%@\";\n", encodedPath];
  NSArray *matches = [include matchesInString:source
                                      options:0
                                        range:NSMakeRange (0, [source length])];
  NSUInteger cursor = 0;
  for (NSTextCheckingResult *match in matches)
    {
      [expanded appendString:[source substringWithRange:NSMakeRange (cursor, [match range].location
                                                                               - cursor)]];
      NSString *relative = [source substringWithRange:[match rangeAtIndex:1]];
      NSString *includedPath =
        [[canonical stringByDeletingLastPathComponent] stringByAppendingPathComponent:relative];
      NSString *included = [self expandedSourceAtPath:includedPath
                                               budget:budget
                                                depth:depth + 1
                                               active:active
                                                error:error];
      if (!included)
        {
          [active removeLastObject];
          return nil;
        }
      [expanded appendString:included];
      [expanded appendFormat:@"\n__scoremakerSourceFile \"%@\";\n", encodedPath];
      cursor = NSMaxRange ([match range]);
      if ([expanded lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > ScorefileMaximumBytes)
        {
          [active removeLastObject];
          if (error)
            *error = ScorefileError (@"Expanded ScoreFile exceeds the 32 MiB byte budget.");
          return nil;
        }
    }
  [expanded appendString:[source substringFromIndex:cursor]];
  [active removeLastObject];
  if ([expanded lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > ScorefileMaximumBytes)
    {
      if (error)
        *error = ScorefileError (@"Expanded ScoreFile exceeds the 32 MiB byte budget.");
      return nil;
    }
  return expanded;
}

+ (ScoreDocument *)parseFileAtPath:(NSString *)path error:(NSError **)error
{
  NSTimeInterval deadline =
    [NSDate timeIntervalSinceReferenceDate] + ScorefileMaximumExecutionSeconds;
  [[[NSThread currentThread] threadDictionary] setObject:@(deadline)
                                                  forKey:ScorefileThreadDeadlineKey];
  NSMutableDictionary *budget = [NSMutableDictionary
    dictionaryWithObjectsAndKeys:@0, @"bytes", @0, @"includes", @(deadline), @"deadline", nil];
  NSString *raw = [self expandedSourceAtPath:path
                                      budget:budget
                                       depth:0
                                      active:[NSMutableArray array]
                                       error:error];
  if (!raw)
    {
      [[[NSThread currentThread] threadDictionary] removeObjectForKey:ScorefileThreadDeadlineKey];
      return nil;
    }

  ScoreDocument *document =
    [self parseString:raw
       suggestedTitle:[[path lastPathComponent] stringByDeletingPathExtension]
                error:error];
  [[[NSThread currentThread] threadDictionary] removeObjectForKey:ScorefileThreadDeadlineKey];
  return document;
}

+ (ScoreDocument *)parseString:(NSString *)raw
                suggestedTitle:(NSString *)title
                         error:(NSError **)error
{
  return [self parseString:raw suggestedTitle:title noteSourceRanges:NULL error:error];
}

+ (ScoreDocument *)parseString:(NSString *)raw
                suggestedTitle:(NSString *)title
              noteSourceRanges:(NSArray **)noteRanges
                         error:(NSError **)error
{
  if (noteRanges)
    *noteRanges = nil;
  if (![raw length])
    {
      if (error)
        *error = ScorefileError (@"The score source is empty.");
      return nil;
    }
  if ([raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > ScorefileMaximumBytes)
    {
      if (error)
        *error = ScorefileError (@"ScoreFile exceeds the 32 MiB byte budget.");
      return nil;
    }
  NSNumber *inheritedDeadline =
    [[[NSThread currentThread] threadDictionary] objectForKey:ScorefileThreadDeadlineKey];
  NSTimeInterval parseDeadline = inheritedDeadline ? [inheritedDeadline doubleValue]
                                                   : [NSDate timeIntervalSinceReferenceDate]
                                                       + ScorefileMaximumExecutionSeconds;

  NSError *lexicalError = ScorefileLexicalError (raw);
  if (lexicalError)
    {
      if (error)
        *error = lexicalError;
      return nil;
    }

  NSMutableDictionary *variables =
    [NSMutableDictionary dictionaryWithObjectsAndKeys:@(M_PI), @"pi", @(M_E), @"e", nil];
  NSArray *pitchClasses = [NSArray arrayWithObjects:@"c", @"cs", @"d", @"ds", @"e", @"f", @"fs",
                                                    @"g", @"gs", @"a", @"as", @"b", nil];
  for (NSInteger octave = -1; octave <= 9; octave++)
    for (NSInteger pitchClass = 0; pitchClass < 12; pitchClass++)
      {
        NSInteger midi = (octave + 1) * 12 + pitchClass;
        double frequency = 440.0 * pow (2.0, ((double)midi - 69.0) / 12.0);
        NSString *name = [NSString
          stringWithFormat:@"%@%ld", [pitchClasses objectAtIndex:pitchClass], (long)octave];
        [variables setObject:@(frequency) forKey:name];
      }
  NSString *strippedContent = StripComments (raw);
  unsigned long long sourceSeed = ScorefileStableSeed (strippedContent);
  [variables setObject:[NSNumber numberWithUnsignedLongLong:sourceSeed]
                forKey:ScorefileRandomStateKey];
  [variables setObject:[NSNumber numberWithUnsignedLongLong:sourceSeed] forKey:@"randomSeed"];
  NSRegularExpression *scriptMarker = [NSRegularExpression
    regularExpressionWithPattern:
      @"(?m)(?:^|[;{}])\\s*(?:while\\s*\\(|if\\s*\\(|print\\s+|int\\s+|double\\s+)"
                         options:NSRegularExpressionCaseInsensitive
                           error:NULL];
  BOOL hasScript = [scriptMarker firstMatchInString:strippedContent
                                            options:0
                                              range:NSMakeRange (0, [strippedContent length])]
                   != nil;
  NSString *content = hasScript
                        ? ExpandScorefileScript (strippedContent, variables, parseDeadline, error)
                        : strippedContent;
  if (!content)
    return nil;
  NSArray *statements = ScorefileStatements (content);
  if ([statements count] > ScorefileMaximumStatements)
    {
      if (error)
        *error = ScorefileError (@"ScoreFile contains more than 250,000 statements.");
      return nil;
    }
  NSArray *statementRanges =
    [content isEqualToString:strippedContent] ? ScorefileStatementRanges (raw) : [NSArray array];
  NSMutableArray *capturedNoteRanges = noteRanges ? [NSMutableArray array] : nil;
  NSMutableDictionary *activeNotes = [NSMutableDictionary dictionary];
  NSMutableDictionary *partDefaults = [NSMutableDictionary dictionary];
  ScoreDocument *document = [[[ScoreDocument alloc] init] autorelease];
  [document setTitle:[title length] ? title : @"Untitled"];
  [document setTicksPerQuarter:480];
  NSDictionary *metadata = ScoreMakerMetadataFromScorefile (raw);
  NSDictionary *structure = ScoreMakerJSONCommentFromScorefile (raw, ScoreMakerStructureMarker);
  NSString *metadataTitle = [metadata objectForKey:@"title"];
  NSString *metadataTitleFont = [metadata objectForKey:@"titleFont"];
  NSString *metadataComposer = [metadata objectForKey:@"composer"];
  NSString *metadataAnnotation = [metadata objectForKey:@"annotation"];
  NSDictionary *storedCompatibility = [metadata objectForKey:@"scorefileCompatibility"];
  if ([storedCompatibility isKindOfClass:[NSDictionary class]])
    [document
      setScorefileCompatibility:[NSMutableDictionary dictionaryWithDictionary:storedCompatibility]];
  [[document scorefileCompatibility] setObject:raw forKey:@"originalSource"];
  if (hasScript)
    [[document scorefileCompatibility] setObject:@YES forKey:@"algorithmicSource"];
  if ([metadataTitle isKindOfClass:[NSString class]])
    [document setTitle:metadataTitle];
  if ([metadataTitleFont isKindOfClass:[NSString class]])
    [document setTitleFontName:metadataTitleFont];
  if ([metadataComposer isKindOfClass:[NSString class]])
    [document setComposer:metadataComposer];
  if ([metadataAnnotation isKindOfClass:[NSString class]])
    [document setAnnotationText:metadataAnnotation];

  double tempoBPM = 120.0;
  double currentTime = 0.0;
  BOOL inBody = NO;
  NSUInteger trackForPart = 0;
  NSUInteger parsedNoteCount = 0;
  NSString *currentSourcePath = nil;
  NSMutableDictionary *partTracks = [NSMutableDictionary dictionary];

  for (NSUInteger statementIndex = 0; statementIndex < [statements count]; statementIndex++)
    {
      if ((statementIndex & 1023U) == 0 && ScorefileDeadlineExceeded (parseDeadline, error))
        return nil;
      NSString *rawStatement = [statements objectAtIndex:statementIndex];
      NSValue *sourceRange = statementIndex < [statementRanges count]
                               ? [statementRanges objectAtIndex:statementIndex]
                               : nil;
      NSString *statement = Trim (rawStatement);
      if ([statement hasPrefix:@"/*__SM_TRACE:"])
        {
          NSScanner *traceScanner = [NSScanner scannerWithString:statement];
          NSInteger traceLocation = 0, traceLength = 0;
          if ([traceScanner scanString:@"/*__SM_TRACE:" intoString:NULL] &&
              [traceScanner scanInteger:&traceLocation] &&
              [traceScanner scanString:@":" intoString:NULL] &&
              [traceScanner scanInteger:&traceLength] &&
              [traceScanner scanString:@"*/" intoString:NULL])
            {
              NSUInteger strippedStart = (NSUInteger)MAX (0, traceLocation);
              NSUInteger strippedEnd = strippedStart + (NSUInteger)MAX (0, traceLength);
              NSUInteger originalStart
                = ScorefileOriginalIndexForCommentStrippedIndex (raw, strippedStart);
              NSUInteger originalEnd
                = ScorefileOriginalIndexForCommentStrippedIndex (raw, strippedEnd);
              sourceRange =
                [NSValue valueWithRange:NSMakeRange (originalStart, originalEnd >= originalStart
                                                                      ? originalEnd - originalStart
                                                                      : 0)];
              statement = Trim ([statement substringFromIndex:[traceScanner scanLocation]]);
            }
        }
      if ([statement length] == 0)
        {
          continue;
        }
      NSString *encodedSourcePath = QuotedStringValue (statement, @"__scoremakerSourceFile ");
      if (encodedSourcePath)
        {
          NSData *pathData = [[[NSData alloc] initWithBase64EncodedString:encodedSourcePath
                                                                  options:0] autorelease];
          NSString *decodedPath
            = pathData ? [[[NSString alloc] initWithData:pathData
                                                encoding:NSUTF8StringEncoding] autorelease]
                       : nil;
          if ([decodedPath length])
            {
              currentSourcePath = decodedPath;
              NSMutableArray *files =
                [[document scorefileCompatibility] objectForKey:@"sourceFiles"];
              if (![files isKindOfClass:[NSMutableArray class]])
                {
                  files = files ? [NSMutableArray arrayWithArray:files] : [NSMutableArray array];
                  [[document scorefileCompatibility] setObject:files forKey:@"sourceFiles"];
                }
              if (![files containsObject:decodedPath])
                [files addObject:decodedPath];
            }
          continue;
        }
      NSString *scoreTitle = StringVariableValue (statement, @"scoreTitle");
      if (scoreTitle)
        {
          [document setTitle:scoreTitle];
          continue;
        }
      NSString *scoreComposer = StringVariableValue (statement, @"scoreComposer");
      if (scoreComposer)
        {
          [document setComposer:scoreComposer];
          continue;
        }
      NSString *scoreAnnotation = StringVariableValue (statement, @"scoreAnnotation");
      if (scoreAnnotation)
        {
          [document setAnnotationText:scoreAnnotation];
          continue;
        }
      NSString *annotation = QuotedStringValue (statement, @"annotation ");
      if (annotation)
        {
          [document setAnnotationText:annotation];
          continue;
        }
      NSString *composer = QuotedStringValue (statement, @"composer ");
      if (!composer)
        composer = QuotedStringValue (statement, @"author ");
      if (composer)
        {
          [document setComposer:composer];
          continue;
        }
      NSString *titleFont = QuotedStringValue (statement, @"titleFont ");
      if (titleFont)
        {
          [document setTitleFontName:titleFont];
          continue;
        }
      NSString *title = QuotedStringValue (statement, @"title ");
      if (title)
        {
          [document setTitle:title];
          continue;
        }
      if ([statement caseInsensitiveCompare:@"BEGIN"] == NSOrderedSame)
        {
          inBody = YES;
          continue;
        }
      if ([statement caseInsensitiveCompare:@"END"] == NSOrderedSame)
        {
          break;
        }

      if (StringHasPrefix (statement, @"info "))
        {
          NSRange tempoRange = [statement rangeOfString:@"tempo:" options:NSCaseInsensitiveSearch];
          if (tempoRange.location != NSNotFound)
            {
              NSString *tempoString =
                [statement substringFromIndex:tempoRange.location + tempoRange.length];
              NSScanner *scanner = [NSScanner scannerWithString:tempoString];
              double scannedTempo = 0.0;
              if ([scanner scanDouble:&scannedTempo] && scannedTempo > 0.0)
                {
                  tempoBPM = scannedTempo;
                  [document setTempoMicrosecondsPerQuarter:(NSUInteger)(60000000.0 / tempoBPM)];
                }
            }
          NSRange timingRange = [statement rangeOfString:@"timeSignature:"
                                                 options:NSCaseInsensitiveSearch];
          if (timingRange.location != NSNotFound)
            {
              NSString *timingString =
                [statement substringFromIndex:timingRange.location + timingRange.length];
              NSScanner *scanner = [NSScanner scannerWithString:timingString];
              NSInteger numerator = 0;
              NSInteger denominator = 0;
              NSString *slash = nil;
              if ([scanner scanInteger:&numerator] && [scanner scanString:@"/" intoString:&slash] &&
                  [scanner scanInteger:&denominator] && numerator > 0 && denominator > 0)
                {
                  [document setTimeSignatureNumerator:(NSUInteger)numerator];
                  [document setTimeSignatureDenominator:(NSUInteger)denominator];
                }
            }
          continue;
        }

      if (StringHasPrefix (statement, @"var "))
        {
          NSString *assignment = Trim ([statement substringFromIndex:4]);
          NSArray *parts = [assignment componentsSeparatedByString:@"="];
          if ([parts count] >= 2)
            {
              NSString *name = Trim ([parts objectAtIndex:0]);
              NSString *expr = Trim ([parts objectAtIndex:1]);
              BOOL ok = NO;
              double value = EvaluateExpression (expr, variables, &ok);
              if (ok && [name length] > 0)
                {
                  SetScorefileVariable (variables, name, value);
                }
            }
          continue;
        }

      if (!inBody && StringHasPrefix (statement, @"part "))
        {
          NSString *partDeclaration = Trim ([statement substringFromIndex:5]);
          NSArray *partNames = [partDeclaration componentsSeparatedByString:@","];
          NSEnumerator *partNameEnumerator = [partNames objectEnumerator];
          NSString *rawPartName = nil;
          while ((rawPartName = [partNameEnumerator nextObject]) != nil)
            {
              NSString *partName = Trim (rawPartName);
              NSArray *partTokens =
                [partName componentsSeparatedByCharactersInSet:[NSCharacterSet
                                                                 whitespaceAndNewlineCharacterSet]];
              partName = [partTokens count] > 0 ? [partTokens objectAtIndex:0] : @"part";
              if ([partName length] == 0 || [partTracks objectForKey:partName])
                continue;
              NSNumber *trackNumber = [NSNumber numberWithUnsignedInteger:trackForPart++];
              [partTracks setObject:trackNumber forKey:partName];
              [document setName:partName forTrack:[trackNumber integerValue]];
              NSNumber *program = GeneralMidiProgramForDescriptor (partName);
              if (program)
                {
                  [document setProgram:program forTrack:[trackNumber integerValue]];
                }
            }
          continue;
        }

      if (!inBody)
        {
          NSString *lower = [statement lowercaseString];
          NSString *category = nil;
          if ([lower hasPrefix:@"envelope "])
            category = @"envelopes";
          else if ([lower hasPrefix:@"wavetable "])
            category = @"wavetables";
          else if ([lower hasPrefix:@"tuning "] || [lower hasPrefix:@"tune "])
            category = @"tunings";
          if (category)
            {
              NSMutableArray *items = [[document scorefileCompatibility] objectForKey:category];
              if (![items isKindOfClass:[NSMutableArray class]])
                {
                  items = items ? [NSMutableArray arrayWithArray:items] : [NSMutableArray array];
                  [[document scorefileCompatibility] setObject:items forKey:category];
                }
              [items addObject:statement];
              NSString *objectKind = [category isEqualToString:@"envelopes"]    ? @"envelope"
                                     : [category isEqualToString:@"wavetables"] ? @"wavetable"
                                                                                : @"tuning";
              NSDictionary *numericObject = ScorefileNamedNumericObject (statement, objectKind);
              if (numericObject)
                {
                  NSString *objectsKey = [category stringByAppendingString:@"Objects"];
                  NSMutableDictionary *objects =
                    [[document scorefileCompatibility] objectForKey:objectsKey];
                  if (![objects isKindOfClass:[NSMutableDictionary class]])
                    {
                      objects = objects ? [NSMutableDictionary dictionaryWithDictionary:objects]
                                        : [NSMutableDictionary dictionary];
                      [[document scorefileCompatibility] setObject:objects forKey:objectsKey];
                    }
                  [objects setObject:numericObject forKey:[numericObject objectForKey:@"name"]];
                }
              continue;
            }
          NSArray *partInfoTokens = [statement
            componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
          NSString *partName = [partInfoTokens count] > 0 ? [partInfoTokens objectAtIndex:0] : nil;
          NSNumber *trackNumber = partName ? [partTracks objectForKey:partName] : nil;
          if (trackNumber)
            {
              NSString *instrumentDescriptor = InstrumentDescriptorInParameters (statement);
              if ([instrumentDescriptor length])
                {
                  NSMutableDictionary *patches =
                    [[document scorefileCompatibility] objectForKey:@"synthPatches"];
                  if (![patches isKindOfClass:[NSMutableDictionary class]])
                    {
                      patches = patches ? [NSMutableDictionary dictionaryWithDictionary:patches]
                                        : [NSMutableDictionary dictionary];
                      [[document scorefileCompatibility] setObject:patches forKey:@"synthPatches"];
                    }
                  [patches setObject:instrumentDescriptor forKey:[trackNumber stringValue]];
                }
              NSNumber *program = instrumentDescriptor
                                    ? GeneralMidiProgramForDescriptor (instrumentDescriptor)
                                    : nil;
              if (program)
                {
                  [document setProgram:program forTrack:[trackNumber integerValue]];
                }
            }
          continue;
        }

      if (StringHasPrefix (statement, @"t "))
        {
          NSString *expr = Trim ([statement substringFromIndex:2]);
          BOOL relative = [expr hasPrefix:@"+"] || [expr hasPrefix:@"-"];
          BOOL ok = NO;
          double value = EvaluateExpression (expr, variables, &ok);
          if (ok)
            {
              currentTime = relative ? currentTime + value : value;
              if (currentTime < 0.0)
                currentTime = 0.0;
            }
          else
            {
              if (error)
                *error = ScorefileErrorAtRange (@"Invalid time expression.", raw,
                                                [sourceRange rangeValue]);
              return nil;
            }
          continue;
        }

      NSRange open = [statement rangeOfString:@"("];
      NSRange anyClose = [statement rangeOfString:@")"];
      NSRange close = [statement
        rangeOfString:@")"
              options:0
                range:NSMakeRange (
                        open.location == NSNotFound ? 0 : open.location,
                        open.location == NSNotFound ? 0 : [statement length] - open.location)];
      if (open.location == NSNotFound || close.location == NSNotFound
          || close.location <= open.location)
        {
          if ((open.location == NSNotFound) != (anyClose.location == NSNotFound))
            {
              if (error)
                *error = ScorefileErrorAtRange (@"Unmatched event parenthesis.", raw,
                                                [sourceRange rangeValue]);
              return nil;
            }
          continue;
        }

      NSString *partName = Trim ([statement substringToIndex:open.location]);
      NSArray *partTokens = [partName
        componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      partName = [partTokens count] > 0 ? [partTokens objectAtIndex:0] : @"part";
      NSNumber *trackNumber = [partTracks objectForKey:partName];
      if (!trackNumber)
        {
          trackNumber = [NSNumber numberWithUnsignedInteger:trackForPart++];
          [partTracks setObject:trackNumber forKey:partName];
          [document setName:partName forTrack:[trackNumber integerValue]];
          NSNumber *program = GeneralMidiProgramForDescriptor (partName);
          if (program)
            {
              [document setProgram:program forTrack:[trackNumber integerValue]];
            }
        }

      NSString *event = Trim ([statement
        substringWithRange:NSMakeRange (open.location + 1, close.location - open.location - 1)]);
      NSString *params = [statement substringFromIndex:close.location + 1];
      NSMutableDictionary *eventParameters = ScorefileParameters (params);
      for (NSString *parameterName in [[[eventParameters allKeys] copy] autorelease])
        {
          NSString *parameterValue = [eventParameters objectForKey:parameterName];
          BOOL parameterOK = NO;
          double evaluated = EvaluateExpression (parameterValue, variables, &parameterOK);
          if (parameterOK)
            [eventParameters setObject:[NSString stringWithFormat:@"%.17g", evaluated]
                                forKey:parameterName];
        }
      NSString *instrumentDescriptor = InstrumentDescriptorInParameters (params);
      if ([instrumentDescriptor length] > 0)
        {
          NSNumber *program = GeneralMidiProgramForDescriptor (instrumentDescriptor);
          if (program)
            {
              [document setProgram:program forTrack:[trackNumber integerValue]];
            }
        }
      NSString *channelDescriptor = instrumentDescriptor
                                      ? instrumentDescriptor
                                      : [document nameForTrack:[trackNumber integerValue]];
      NSInteger scorefileChannel
        = MidiChannelForScorefileTrack ([trackNumber integerValue], channelDescriptor);
      NSString *pitchString = nil;
      BOOL pitchIsFrequency = NO;
      NSString *keyNumValue = ScorefileDictionaryValue (eventParameters, @"keyNum");
      NSString *frequencyValue = ScorefileDictionaryValue (eventParameters, @"freq");
      if (keyNumValue || frequencyValue)
        {
          pitchIsFrequency = frequencyValue != nil;
          pitchString = pitchIsFrequency ? frequencyValue : keyNumValue;
        }

      BOOL pitchOK = NO;
      NSInteger pitch = 60;
      double playbackFrequency = 0.0;
      if (pitchString)
        {
          if (pitchIsFrequency)
            {
              BOOL frequencyOK = NO;
              playbackFrequency = EvaluateExpression (pitchString, variables, &frequencyOK);
              pitch = PitchForFrequency (pitchString, variables, &pitchOK);
              if (!frequencyOK || playbackFrequency <= 0.0)
                playbackFrequency = 0.0;
            }
          else
            {
              BOOL numericOK = NO;
              double numericKey = EvaluateExpression (pitchString, variables, &numericOK);
              if (numericOK)
                {
                  pitch = (NSInteger)llround (numericKey);
                  pitchOK = YES;
                  if (fabs (numericKey - (double)pitch) > 0.000001)
                    playbackFrequency = 440.0 * pow (2.0, (numericKey - 69.0) / 12.0);
                }
              else
                pitch = PitchForName (pitchString, &pitchOK);
            }
        }
      if (pitchString && !pitchOK)
        {
          if (error)
            *error = ScorefileErrorAtRange (@"Invalid pitch value.", raw, [sourceRange rangeValue]);
          return nil;
        }
      double ticksPerBeat = (double)[document ticksPerQuarter];
      NSUInteger currentTick = (NSUInteger)llround (currentTime * ticksPerBeat);

      if (StringHasPrefix (event, @"mute"))
        {
          NSArray *keys = [[activeNotes allKeys] copy];
          for (NSString *activeKey in keys)
            if ([activeKey hasPrefix:[partName stringByAppendingString:@":"]])
              {
                ScoreNote *note = [activeNotes objectForKey:activeKey];
                if (currentTick > [note startTick])
                  [note setDurationTicks:currentTick - [note startTick]];
                [activeNotes removeObjectForKey:activeKey];
              }
          [keys release];
          continue;
        }

      if (StringHasPrefix (event, @"noteOff"))
        {
          NSArray *eventParts = [event
            componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
          NSString *tag = [eventParts count] > 1 ? [eventParts objectAtIndex:1] : @"0";
          NSString *key = [NSString stringWithFormat:@"%@:%@", partName, tag];
          ScoreNote *note = [activeNotes objectForKey:key];
          if (note && currentTick > [note startTick])
            {
              [note setDurationTicks:currentTick - [note startTick]];
              if ([note startTick] + [note durationTicks] > [document totalTicks])
                {
                  [document setTotalTicks:[note startTick] + [note durationTicks]];
                }
              [activeNotes removeObjectForKey:key];
            }
          continue;
        }

      NSArray *eventWords = [event
        componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if (StringHasPrefix (event, @"noteUpdate") && [eventWords count] < 2)
        {
          NSMutableDictionary *defaults = [partDefaults objectForKey:partName];
          if (!defaults)
            {
              defaults = [NSMutableDictionary dictionary];
              [partDefaults setObject:defaults forKey:partName];
            }
          [defaults addEntriesFromDictionary:eventParameters];
          NSArray *keys = [[activeNotes allKeys] copy];
          for (NSString *activeKey in keys)
            if ([activeKey hasPrefix:[partName stringByAppendingString:@":"]])
              {
                ScoreNote *previous = [activeNotes objectForKey:activeKey];
                if (currentTick > [previous startTick])
                  [previous setDurationTicks:currentTick - [previous startTick]];
                ScoreNote *continuation = [[previous copy] autorelease];
                [continuation setStartTick:currentTick];
                [continuation setDurationTicks:[document ticksPerQuarter]];
                NSMutableDictionary *combined =
                  [NSMutableDictionary dictionaryWithDictionary:[previous performanceParameters]];
                [combined addEntriesFromDictionary:eventParameters];
                [continuation setPerformanceParameters:combined];
                NSString *amp = ScorefileDictionaryValue (combined, @"amp");
                if (amp)
                  {
                    BOOL ampOK = NO;
                    double value = EvaluateExpression (amp, variables, &ampOK);
                    if (ampOK)
                      [continuation
                        setVelocity:(NSUInteger)llround (127.0 * MIN (1.0, MAX (0.0, value)))];
                  }
                if (++parsedNoteCount > ScorefileMaximumNotes)
                  {
                    if (error)
                      *error = ScorefileError (@"ScoreFile generates more than 250,000 notes.");
                    return nil;
                  }
                if ([currentSourcePath length])
                  [continuation setProvenance:currentSourcePath];
                [[document notes] addObject:continuation];
                [activeNotes setObject:continuation forKey:activeKey];
              }
          [keys release];
          continue;
        }

      if (StringHasPrefix (event, @"noteOn") || StringHasPrefix (event, @"noteUpdate"))
        {
          NSArray *eventParts = [event
            componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
          NSString *tag = [eventParts count] > 1 ? [eventParts objectAtIndex:1] : partName;
          NSString *key = [NSString stringWithFormat:@"%@:%@", partName, tag];
          ScoreNote *previous = [activeNotes objectForKey:key];
          if (previous && currentTick > [previous startTick])
            {
              [previous setDurationTicks:currentTick - [previous startTick]];
            }
          if (pitchOK || (StringHasPrefix (event, @"noteUpdate") && previous))
            {
              ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
              [note setPitch:pitchOK ? pitch : [previous pitch]];
              [note
                setPlaybackFrequency:pitchOK ? playbackFrequency : [previous playbackFrequency]];
              [note
                setAccidental:pitchOK ? AccidentalForName (pitchString) : [previous accidental]];
              [note setChannel:scorefileChannel];
              [note setTrack:[trackNumber integerValue]];
              [note setStartTick:currentTick];
              [note setDurationTicks:[document ticksPerQuarter]];
              if (previous)
                [note setVelocity:[previous velocity]];
              NSMutableDictionary *combined =
                [partDefaults objectForKey:partName]
                  ? [NSMutableDictionary
                      dictionaryWithDictionary:[partDefaults objectForKey:partName]]
                  : [NSMutableDictionary dictionary];
              if (previous)
                [combined addEntriesFromDictionary:[previous performanceParameters]];
              [combined addEntriesFromDictionary:eventParameters];
              [note setPerformanceParameters:combined];
              NSString *amp = ScorefileDictionaryValue (combined, @"amp");
              if (amp)
                {
                  BOOL ampOK = NO;
                  double value = EvaluateExpression (amp, variables, &ampOK);
                  if (ampOK)
                    [note setVelocity:(NSUInteger)llround (127.0 * MIN (1.0, MAX (0.0, value)))];
                }
              if (++parsedNoteCount > ScorefileMaximumNotes)
                {
                  if (error)
                    *error = ScorefileError (@"ScoreFile generates more than 250,000 notes.");
                  return nil;
                }
              if ([currentSourcePath length])
                [note setProvenance:currentSourcePath];
              [[document notes] addObject:note];
              if (sourceRange)
                {
                  NSMutableDictionary *capture = [NSMutableDictionary
                    dictionaryWithObjectsAndKeys:note, @"note", sourceRange, @"range", nil];
                  if ([currentSourcePath length])
                    [capture setObject:currentSourcePath forKey:@"sourcePath"];
                  [capturedNoteRanges addObject:capture];
                }
              [activeNotes setObject:note forKey:key];
            }
          continue;
        }

      BOOL durationOK = NO;
      double durationSeconds = EvaluateExpression (event, variables, &durationOK);
      if (durationOK && durationSeconds > 0.0 && (pitchOK || !pitchString))
        {
          ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
          [note setRest:!pitchOK];
          [note setPitch:pitchOK ? pitch : 60];
          [note setPlaybackFrequency:pitchOK ? playbackFrequency : 0.0];
          if (pitchOK && !pitchIsFrequency)
            {
              [note setAccidental:AccidentalForName (pitchString)];
            }
          [note setChannel:scorefileChannel];
          [note setTrack:[trackNumber integerValue]];
          NSMutableDictionary *combined =
            [partDefaults objectForKey:partName]
              ? [NSMutableDictionary dictionaryWithDictionary:[partDefaults objectForKey:partName]]
              : [NSMutableDictionary dictionary];
          [combined addEntriesFromDictionary:eventParameters];
          [note setPerformanceParameters:combined];
          NSString *amp = ScorefileDictionaryValue (combined, @"amp");
          if (amp)
            {
              BOOL ampOK = NO;
              double value = EvaluateExpression (amp, variables, &ampOK);
              if (ampOK)
                [note setVelocity:(NSUInteger)llround (127.0 * MIN (1.0, MAX (0.0, value)))];
            }
          [note setStartTick:currentTick];
          [note setDurationTicks:MAX ((NSUInteger)1,
                                      (NSUInteger)llround (durationSeconds * ticksPerBeat))];
          [note setSlurStart:([params rangeOfString:@"slurStart:1" options:NSCaseInsensitiveSearch]
                                .location
                              != NSNotFound)];
          [note setSlurEnd:([params rangeOfString:@"slurStop:1" options:NSCaseInsensitiveSearch]
                              .location
                            != NSNotFound)];
          if (++parsedNoteCount > ScorefileMaximumNotes)
            {
              if (error)
                *error = ScorefileError (@"ScoreFile generates more than 250,000 notes.");
              return nil;
            }
          if ([currentSourcePath length])
            [note setProvenance:currentSourcePath];
          [[document notes] addObject:note];
          if (sourceRange)
            {
              NSMutableDictionary *capture = [NSMutableDictionary
                dictionaryWithObjectsAndKeys:note, @"note", sourceRange, @"range", nil];
              if ([currentSourcePath length])
                [capture setObject:currentSourcePath forKey:@"sourcePath"];
              [capturedNoteRanges addObject:capture];
            }
          if ([note startTick] + [note durationTicks] > [document totalTicks])
            {
              [document setTotalTicks:[note startTick] + [note durationTicks]];
            }
        }
    }

  NSEnumerator *activeNoteEnumerator = [[activeNotes allValues] objectEnumerator];
  ScoreNote *activeNote = nil;
  while ((activeNote = [activeNoteEnumerator nextObject]) != nil)
    {
      if ([activeNote durationTicks] == 0)
        {
          [activeNote setDurationTicks:[document ticksPerQuarter]];
        }
      if ([activeNote startTick] + [activeNote durationTicks] > [document totalTicks])
        {
          [document setTotalTicks:[activeNote startTick] + [activeNote durationTicks]];
        }
    }

  if ([[document notes] count] == 0)
    {
      if (error)
        *error = ScorefileError (@"No renderable notes were found in the scorefile.");
      return nil;
    }

  [[document notes] sortUsingSelector:@selector (compareScoreNote:)];
  if (structure)
    {
      ApplyScoreMakerStructure (document, structure);
    }
  else
    {
      [document buildDefaultMeasures];
    }
  [document rebuildStructuredPartsFromLegacyTracks];
  if (noteRanges)
    *noteRanges = [[capturedNoteRanges copy] autorelease];
  return document;
}

+ (BOOL)writeDocument:(ScoreDocument *)document
         toFileAtPath:(NSString *)path
                error:(NSError **)error
{
  NSData *data = [self dataForDocument:document error:error];
  if (!data)
    {
      return NO;
    }
  return [data writeToFile:path options:NSDataWritingAtomic error:error];
}

+ (NSData *)dataForDocument:(ScoreDocument *)document error:(NSError **)error
{
  if (!document)
    {
      if (error)
        *error = ScorefileError (@"There is no score to save.");
      return nil;
    }

  NSDictionary *compatibility = [document scorefileCompatibility];
  NSString *algorithmicSource = [compatibility objectForKey:@"originalSource"];
  if ([[compatibility objectForKey:@"algorithmicSource"] boolValue] && [algorithmicSource length])
    {
      NSMutableString *preserved = [NSMutableString
        stringWithString:@"/* Written by ScoreMaker; algorithmic source preserved. */\n\n"];
      NSString *metadataComment = ScoreMakerMetadataComment (document, error);
      if (!metadataComment)
        return nil;
      [preserved appendString:metadataComment];
      if ([[document measures] count] == 0)
        [document buildDefaultMeasures];
      NSString *structureComment = ScoreMakerStructureComment (document, error);
      if (!structureComment)
        return nil;
      [preserved appendString:structureComment];
      [preserved appendString:algorithmicSource];
      return [preserved dataUsingEncoding:NSUTF8StringEncoding];
    }

  double tempoBPM = [document tempoMicrosecondsPerQuarter] > 0
                      ? 60000000.0 / (double)[document tempoMicrosecondsPerQuarter]
                      : 120.0;
  NSMutableString *output = [NSMutableString string];
  [output appendString:@"/* Written by ScoreMaker. */\n\n"];
  NSString *metadataComment = ScoreMakerMetadataComment (document, error);
  if (!metadataComment)
    return nil;
  [output appendString:metadataComment];
  if ([[document measures] count] == 0)
    [document buildDefaultMeasures];
  NSString *structureComment = ScoreMakerStructureComment (document, error);
  if (!structureComment)
    return nil;
  [output appendString:structureComment];
  if ([[document title] length] > 0)
    {
      [output
        appendFormat:@"string scoreTitle = \"%@\";\n", EscapeScorefileString ([document title])];
    }
  if ([[document composer] length] > 0)
    {
      [output appendFormat:@"string scoreComposer = \"%@\";\n",
                           EscapeScorefileString ([document composer])];
    }
  if ([[document annotationText] length] > 0)
    {
      [output appendFormat:@"string scoreAnnotation = \"%@\";\n",
                           EscapeScorefileString ([document annotationText])];
    }
  [output appendFormat:@"info tempo:%.6g timeSignature:%lu/%lu;\n", tempoBPM,
                       (unsigned long)[document timeSignatureNumerator],
                       (unsigned long)[document timeSignatureDenominator]];
  for (NSString *category in
       [NSArray arrayWithObjects:@"envelopes", @"wavetables", @"tunings", nil])
    for (NSString *declaration in [[document scorefileCompatibility] objectForKey:category])
      [output appendFormat:@"%@;\n", declaration];
  NSMutableDictionary *partIdentifiers = [NSMutableDictionary dictionary];
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
  [tracks sortUsingSelector:@selector (compare:)];
  NSEnumerator *trackEnumerator = [tracks objectEnumerator];
  NSNumber *track = nil;
  while ((track = [trackEnumerator nextObject]) != nil)
    {
      NSString *name = [document nameForTrack:[track integerValue]];
      if ([name length] == 0)
        {
          name = [NSString stringWithFormat:@"part%@", track];
        }
      NSString *identifier = ScorefileIdentifierForPartName (name);
      NSString *base = identifier;
      NSUInteger suffix = 2;
      while ([[partIdentifiers allValues] containsObject:identifier])
        {
          identifier = [NSString stringWithFormat:@"%@_%lu", base, (unsigned long)suffix++];
        }
      [partIdentifiers setObject:identifier forKey:track];
      NSNumber *program = [document programForTrack:[track integerValue]];
      [output appendFormat:@"part %@;\n", identifier];
      if (program)
        [output appendFormat:@"%@ program:%ld;\n", identifier, (long)[program integerValue]];
    }
  [output appendString:@"\nBEGIN;\n\n"];

  NSUInteger lastTick = NSNotFound;
  noteEnumerator = [[document notes] objectEnumerator];
  while ((note = [noteEnumerator nextObject]) != nil)
    {
      if ([note startTick] != lastTick)
        {
          double time = (double)[note startTick] / (double)[document ticksPerQuarter];
          [output appendFormat:@"t %.12g;\n", time];
          lastTick = [note startTick];
        }
      double duration
        = (double)MAX ((NSUInteger)1, [note durationTicks]) / (double)[document ticksPerQuarter];
      NSString *identifier =
        [partIdentifiers objectForKey:[NSNumber numberWithInteger:[note track]]];
      if (!identifier)
        {
          identifier = @"score";
        }
      if ([note isRest])
        {
          [output appendFormat:@"%@ (%.12g);\n", identifier, duration];
        }
      else
        {
          NSString *pitchParameter =
            [note playbackFrequency] > 0.0
              ? [NSString stringWithFormat:@"freq:%.12g", [note playbackFrequency]]
              : [NSString stringWithFormat:@"keyNum:%@k",
                                           NoteNameForPitch ([note pitch], [note accidental])];
          NSMutableString *performance = [NSMutableString string];
          NSArray *parameterNames = [[[note performanceParameters] allKeys]
            sortedArrayUsingSelector:@selector (caseInsensitiveCompare:)];
          for (NSString *name in parameterNames)
            {
              if ([name caseInsensitiveCompare:@"keyNum"] == NSOrderedSame ||
                  [name caseInsensitiveCompare:@"freq"] == NSOrderedSame ||
                  [name caseInsensitiveCompare:@"slurStart"] == NSOrderedSame ||
                  [name caseInsensitiveCompare:@"slurStop"] == NSOrderedSame)
                continue;
              [performance
                appendFormat:@" %@:%@", name, [[note performanceParameters] objectForKey:name]];
            }
          [output appendFormat:@"%@ (%.12g) %@%@%@%@;\n", identifier, duration, pitchParameter,
                               performance, [note slurStart] ? @" slurStart:1" : @"",
                               [note slurEnd] ? @" slurStop:1" : @""];
        }
    }

  [output appendString:@"\nEND;\n"];
  NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
  if (!data && error)
    {
      *error = ScorefileError (@"The scorefile could not be encoded as UTF-8.");
    }
  return data;
}

@end
