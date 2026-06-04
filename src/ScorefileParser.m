#import "ScorefileParser.h"
#import <math.h>

static NSString * const ScorefileParserErrorDomain = @"ScoreMakerScorefileParser";

static NSError *ScorefileError(NSString *message)
{
    NSDictionary *info = [NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
    return [NSError errorWithDomain:ScorefileParserErrorDomain code:1 userInfo:info];
}

static NSString *StripComments(NSString *input)
{
    NSMutableString *output = [NSMutableString string];
    NSUInteger length = [input length];
    BOOL inComment = NO;
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [input characterAtIndex:i];
        unichar next = (i + 1 < length) ? [input characterAtIndex:i + 1] : 0;
        if (!inComment && c == '/' && next == '*') {
            inComment = YES;
            i++;
            continue;
        }
        if (inComment && c == '*' && next == '/') {
            inComment = NO;
            i++;
            continue;
        }
        if (!inComment) {
            [output appendFormat:@"%C", c];
        }
    }
    return output;
}

static NSString *Trim(NSString *input)
{
    return [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static double ValueForToken(NSString *token, NSDictionary *variables, BOOL *ok);

static double EvaluateExpression(NSString *expression, NSDictionary *variables, BOOL *ok)
{
    NSString *s = Trim(expression);
    if ([s length] == 0) {
        if (ok) *ok = NO;
        return 0.0;
    }

    double result = 0.0;
    NSInteger sign = 1;
    NSMutableString *token = [NSMutableString string];
    BOOL sawToken = NO;
    for (NSUInteger i = 0; i <= [s length]; i++) {
        unichar c = (i < [s length]) ? [s characterAtIndex:i] : '+';
        BOOL delimiter = (c == '+' || c == '-') && [token length] > 0;
        if (i == [s length] || delimiter) {
            BOOL tokenOK = YES;
            result += (double)sign * ValueForToken(token, variables, &tokenOK);
            if (!tokenOK) {
                if (ok) *ok = NO;
                return 0.0;
            }
            [token setString:@""];
            sawToken = YES;
        }
        if (i == [s length]) {
            break;
        }
        if ((c == '+' || c == '-') && [token length] == 0) {
            sign = (c == '-') ? -1 : 1;
        } else if (c == '+' || c == '-') {
            sign = (c == '-') ? -1 : 1;
        } else if (![[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:c]) {
            [token appendFormat:@"%C", c];
        }
    }

    if (ok) *ok = sawToken;
    return result;
}

static double ValueForToken(NSString *token, NSDictionary *variables, BOOL *ok)
{
    NSString *s = Trim(token);
    NSNumber *variable = [variables objectForKey:s];
    if (variable) {
        if (ok) *ok = YES;
        return [variable doubleValue];
    }

    NSScanner *scanner = [NSScanner scannerWithString:s];
    double value = 0.0;
    if ([scanner scanDouble:&value]) {
        if (ok) *ok = YES;
        return value;
    }

    if (ok) *ok = NO;
    return 0.0;
}

static NSInteger PitchForName(NSString *value, BOOL *ok)
{
    NSString *s = [[Trim(value) lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@","]];
    if ([s hasSuffix:@"k"]) {
        s = [s substringToIndex:[s length] - 1];
    }

    NSScanner *numberScanner = [NSScanner scannerWithString:s];
    NSInteger number = 0;
    if ([numberScanner scanInteger:&number]) {
        if (ok) *ok = YES;
        return number;
    }

    if ([s length] < 2) {
        if (ok) *ok = NO;
        return 60;
    }

    unichar letter = [s characterAtIndex:0];
    NSInteger semitone = 0;
    switch (letter) {
        case 'c': semitone = 0; break;
        case 'd': semitone = 2; break;
        case 'e': semitone = 4; break;
        case 'f': semitone = 5; break;
        case 'g': semitone = 7; break;
        case 'a': semitone = 9; break;
        case 'b': semitone = 11; break;
        default:
            if (ok) *ok = NO;
            return 60;
    }

    NSUInteger octaveIndex = 1;
    if (octaveIndex < [s length]) {
        unichar accidental = [s characterAtIndex:octaveIndex];
        if (accidental == 's' || accidental == '#') {
            semitone++;
            octaveIndex++;
        } else if (accidental == 'f') {
            semitone--;
            octaveIndex++;
        }
    }

    NSMutableString *octaveString = [NSMutableString string];
    while (octaveIndex < [s length]) {
        unichar c = [s characterAtIndex:octaveIndex];
        if ((c >= '0' && c <= '9') || c == '-') {
            [octaveString appendFormat:@"%C", c];
            octaveIndex++;
        } else {
            break;
        }
    }

    if ([octaveString length] == 0) {
        if (ok) *ok = NO;
        return 60;
    }

    NSInteger octave = [octaveString integerValue];
    if (ok) *ok = YES;
    return (octave + 1) * 12 + semitone;
}

static NSInteger PitchForFrequency(NSString *value, NSDictionary *variables, BOOL *ok)
{
    BOOL expressionOK = NO;
    double frequency = EvaluateExpression(value, variables, &expressionOK);
    if (expressionOK && frequency > 0.0) {
        if (ok) *ok = YES;
        return (NSInteger)llround(69.0 + 12.0 * log(frequency / 440.0) / log(2.0));
    }

    return PitchForName(value, ok);
}

static NSString *NoteNameForPitch(NSInteger pitch)
{
    static NSString *names[] = {@"c", @"cs", @"d", @"ds", @"e", @"f", @"fs", @"g", @"gs", @"a", @"as", @"b"};
    NSInteger pc = pitch % 12;
    if (pc < 0) pc += 12;
    NSInteger octave = (pitch / 12) - 1;
    return [NSString stringWithFormat:@"%@%ld", names[pc], (long)octave];
}

static NSString *ScorefileIdentifierForPartName(NSString *name)
{
    NSMutableString *identifier = [NSMutableString string];
    NSCharacterSet *letters = [NSCharacterSet alphanumericCharacterSet];
    for (NSUInteger i = 0; i < [name length]; i++) {
        unichar c = [name characterAtIndex:i];
        if ([letters characterIsMember:c]) {
            [identifier appendFormat:@"%C", c];
        } else if ([identifier length] > 0 && ![identifier hasSuffix:@"_"]) {
            [identifier appendString:@"_"];
        }
    }
    if ([identifier length] == 0) {
        [identifier appendString:@"part"];
    }
    if ([[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[identifier characterAtIndex:0]]) {
        [identifier insertString:@"part_" atIndex:0];
    }
    return identifier;
}

@implementation ScorefileParser

+ (ScoreDocument *)parseFileAtPath:(NSString *)path error:(NSError **)error
{
    NSString *raw = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:error];
    if (!raw) {
        raw = [NSString stringWithContentsOfFile:path encoding:NSISOLatin1StringEncoding error:error];
    }
    if (!raw) {
        return nil;
    }

    NSString *content = StripComments(raw);
    NSArray *statements = [content componentsSeparatedByString:@";"];
    NSMutableDictionary *variables = [NSMutableDictionary dictionary];
    NSMutableDictionary *activeNotes = [NSMutableDictionary dictionary];
    ScoreDocument *document = [[[ScoreDocument alloc] init] autorelease];
    [document setTitle:[path lastPathComponent]];
    [document setTicksPerQuarter:480];

    double tempoBPM = 120.0;
    double currentTime = 0.0;
    BOOL inBody = NO;
    NSUInteger trackForPart = 0;
    NSMutableDictionary *partTracks = [NSMutableDictionary dictionary];

    NSEnumerator *statementEnumerator = [statements objectEnumerator];
    NSString *rawStatement = nil;
    while ((rawStatement = [statementEnumerator nextObject]) != nil) {
        NSString *statement = Trim(rawStatement);
        if ([statement length] == 0) {
            continue;
        }
        if ([statement rangeOfString:@"BEGIN"].location != NSNotFound) {
            inBody = YES;
            continue;
        }
        if ([statement rangeOfString:@"END"].location != NSNotFound) {
            break;
        }

        if ([statement hasPrefix:@"info "]) {
            NSRange tempoRange = [statement rangeOfString:@"tempo:"];
            if (tempoRange.location != NSNotFound) {
                NSString *tempoString = [statement substringFromIndex:tempoRange.location + tempoRange.length];
                NSScanner *scanner = [NSScanner scannerWithString:tempoString];
                double scannedTempo = 0.0;
                if ([scanner scanDouble:&scannedTempo] && scannedTempo > 0.0) {
                    tempoBPM = scannedTempo;
                    [document setTempoMicrosecondsPerQuarter:(NSUInteger)(60000000.0 / tempoBPM)];
                }
            }
            continue;
        }

        if ([statement hasPrefix:@"var "]) {
            NSString *assignment = Trim([statement substringFromIndex:4]);
            NSArray *parts = [assignment componentsSeparatedByString:@"="];
            if ([parts count] >= 2) {
                NSString *name = Trim([parts objectAtIndex:0]);
                NSString *expr = Trim([parts objectAtIndex:1]);
                BOOL ok = NO;
                double value = EvaluateExpression(expr, variables, &ok);
                if (ok && [name length] > 0) {
                    [variables setObject:[NSNumber numberWithDouble:value] forKey:name];
                }
            }
            continue;
        }

        if (!inBody && [statement hasPrefix:@"part "]) {
            NSString *partName = Trim([statement substringFromIndex:5]);
            NSArray *partTokens = [partName componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            partName = [partTokens count] > 0 ? [partTokens objectAtIndex:0] : @"part";
            if ([partName length] > 0 && ![partTracks objectForKey:partName]) {
                NSNumber *trackNumber = [NSNumber numberWithUnsignedInteger:trackForPart++];
                [partTracks setObject:trackNumber forKey:partName];
                [document setName:partName forTrack:[trackNumber integerValue]];
            }
            continue;
        }

        if (!inBody) {
            continue;
        }

        if ([statement hasPrefix:@"t "]) {
            NSString *expr = Trim([statement substringFromIndex:2]);
            BOOL relative = [expr hasPrefix:@"+"] || [expr hasPrefix:@"-"];
            BOOL ok = NO;
            double value = EvaluateExpression(expr, variables, &ok);
            if (ok) {
                currentTime = relative ? currentTime + value : value;
                if (currentTime < 0.0) currentTime = 0.0;
            }
            continue;
        }

        NSRange open = [statement rangeOfString:@"("];
        NSRange close = [statement rangeOfString:@")" options:0 range:NSMakeRange(open.location == NSNotFound ? 0 : open.location, open.location == NSNotFound ? 0 : [statement length] - open.location)];
        if (open.location == NSNotFound || close.location == NSNotFound || close.location <= open.location) {
            continue;
        }

        NSString *partName = Trim([statement substringToIndex:open.location]);
        NSArray *partTokens = [partName componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        partName = [partTokens count] > 0 ? [partTokens objectAtIndex:0] : @"part";
        NSNumber *trackNumber = [partTracks objectForKey:partName];
        if (!trackNumber) {
            trackNumber = [NSNumber numberWithUnsignedInteger:trackForPart++];
            [partTracks setObject:trackNumber forKey:partName];
            [document setName:partName forTrack:[trackNumber integerValue]];
        }

        NSString *event = Trim([statement substringWithRange:NSMakeRange(open.location + 1, close.location - open.location - 1)]);
        NSString *params = [statement substringFromIndex:close.location + 1];
        NSString *pitchString = nil;
        BOOL pitchIsFrequency = NO;
        NSRange keyNumRange = [params rangeOfString:@"keyNum:"];
        NSRange freqRange = [params rangeOfString:@"freq:"];
        if (keyNumRange.location != NSNotFound || freqRange.location != NSNotFound) {
            NSRange paramRange = keyNumRange;
            NSString *paramName = @"keyNum:";
            if (freqRange.location != NSNotFound &&
                (keyNumRange.location == NSNotFound || freqRange.location < keyNumRange.location)) {
                paramRange = freqRange;
                paramName = @"freq:";
                pitchIsFrequency = YES;
            }

            NSString *after = [params substringFromIndex:paramRange.location + [paramName length]];
            NSScanner *scanner = [NSScanner scannerWithString:after];
            NSString *scanned = nil;
            [scanner scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@" ,\t\r\n"] intoString:&scanned];
            pitchString = scanned;
        }

        BOOL pitchOK = NO;
        NSInteger pitch = 60;
        if (pitchString) {
            pitch = pitchIsFrequency ? PitchForFrequency(pitchString, variables, &pitchOK) : PitchForName(pitchString, &pitchOK);
        }
        double ticksPerBeat = (double)[document ticksPerQuarter];
        NSUInteger currentTick = (NSUInteger)llround(currentTime * ticksPerBeat);

        if ([event hasPrefix:@"noteOff"]) {
            NSArray *eventParts = [event componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *tag = [eventParts count] > 1 ? [eventParts objectAtIndex:1] : @"0";
            NSString *key = [NSString stringWithFormat:@"%@:%@", partName, tag];
            ScoreNote *note = [activeNotes objectForKey:key];
            if (note && currentTick > [note startTick]) {
                [note setDurationTicks:currentTick - [note startTick]];
                if ([note startTick] + [note durationTicks] > [document totalTicks]) {
                    [document setTotalTicks:[note startTick] + [note durationTicks]];
                }
                [activeNotes removeObjectForKey:key];
            }
            continue;
        }

        if ([event hasPrefix:@"noteOn"] || ([event hasPrefix:@"noteUpdate"] && pitchOK)) {
            NSArray *eventParts = [event componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *tag = [eventParts count] > 1 ? [eventParts objectAtIndex:1] : partName;
            NSString *key = [NSString stringWithFormat:@"%@:%@", partName, tag];
            ScoreNote *previous = [activeNotes objectForKey:key];
            if (previous && currentTick > [previous startTick]) {
                [previous setDurationTicks:currentTick - [previous startTick]];
            }
            if (pitchOK) {
                ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
                [note setPitch:pitch];
                [note setChannel:0];
                [note setTrack:[trackNumber integerValue]];
                [note setStartTick:currentTick];
                [note setDurationTicks:[document ticksPerQuarter]];
                [[document notes] addObject:note];
                [activeNotes setObject:note forKey:key];
            }
            continue;
        }

        BOOL durationOK = NO;
        double durationSeconds = EvaluateExpression(event, variables, &durationOK);
        if (durationOK && durationSeconds > 0.0 && pitchOK) {
            ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
            [note setPitch:pitch];
            [note setChannel:0];
            [note setTrack:[trackNumber integerValue]];
            [note setStartTick:currentTick];
            [note setDurationTicks:MAX((NSUInteger)1, (NSUInteger)llround(durationSeconds * ticksPerBeat))];
            [[document notes] addObject:note];
            if ([note startTick] + [note durationTicks] > [document totalTicks]) {
                [document setTotalTicks:[note startTick] + [note durationTicks]];
            }
        }
    }

    NSEnumerator *activeNoteEnumerator = [[activeNotes allValues] objectEnumerator];
    ScoreNote *activeNote = nil;
    while ((activeNote = [activeNoteEnumerator nextObject]) != nil) {
        if ([activeNote durationTicks] == 0) {
            [activeNote setDurationTicks:[document ticksPerQuarter]];
        }
        if ([activeNote startTick] + [activeNote durationTicks] > [document totalTicks]) {
            [document setTotalTicks:[activeNote startTick] + [activeNote durationTicks]];
        }
    }

    if ([[document notes] count] == 0) {
        if (error) *error = ScorefileError(@"No renderable notes were found in the scorefile.");
        return nil;
    }

    [[document notes] sortUsingSelector:@selector(compareScoreNote:)];
    return document;
}

+ (BOOL)writeDocument:(ScoreDocument *)document toFileAtPath:(NSString *)path error:(NSError **)error
{
    if (!document) {
        if (error) *error = ScorefileError(@"There is no score to save.");
        return NO;
    }

    double tempoBPM = [document tempoMicrosecondsPerQuarter] > 0 ? 60000000.0 / (double)[document tempoMicrosecondsPerQuarter] : 120.0;
    NSMutableString *output = [NSMutableString string];
    [output appendString:@"/* Written by ScoreMaker. */\n\n"];
    [output appendFormat:@"info tempo:%.6g;\n", tempoBPM];
    NSMutableDictionary *partIdentifiers = [NSMutableDictionary dictionary];
    NSMutableArray *tracks = [NSMutableArray array];
    NSEnumerator *noteEnumerator = [[document notes] objectEnumerator];
    ScoreNote *note = nil;
    while ((note = [noteEnumerator nextObject]) != nil) {
        NSNumber *track = [NSNumber numberWithInteger:[note track]];
        if (![tracks containsObject:track]) {
            [tracks addObject:track];
        }
    }
    [tracks sortUsingSelector:@selector(compare:)];
    NSEnumerator *trackEnumerator = [tracks objectEnumerator];
    NSNumber *track = nil;
    while ((track = [trackEnumerator nextObject]) != nil) {
        NSString *name = [document nameForTrack:[track integerValue]];
        if ([name length] == 0) {
            name = [NSString stringWithFormat:@"part%@", track];
        }
        NSString *identifier = ScorefileIdentifierForPartName(name);
        NSString *base = identifier;
        NSUInteger suffix = 2;
        while ([[partIdentifiers allValues] containsObject:identifier]) {
            identifier = [NSString stringWithFormat:@"%@_%lu", base, (unsigned long)suffix++];
        }
        [partIdentifiers setObject:identifier forKey:track];
        [output appendFormat:@"part %@;\n", identifier];
    }
    [output appendString:@"\nBEGIN;\n\n"];

    NSUInteger lastTick = NSNotFound;
    noteEnumerator = [[document notes] objectEnumerator];
    while ((note = [noteEnumerator nextObject]) != nil) {
        if ([note startTick] != lastTick) {
            double time = (double)[note startTick] / (double)[document ticksPerQuarter];
            [output appendFormat:@"t %.6g;\n", time];
            lastTick = [note startTick];
        }
        double duration = (double)MAX((NSUInteger)1, [note durationTicks]) / (double)[document ticksPerQuarter];
        NSString *identifier = [partIdentifiers objectForKey:[NSNumber numberWithInteger:[note track]]];
        if (!identifier) {
            identifier = @"score";
        }
        [output appendFormat:@"%@ (%.6g) keyNum:%@;\n", identifier, duration, NoteNameForPitch([note pitch])];
    }

    [output appendString:@"\nEND;\n"];
    return [output writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error];
}

@end
