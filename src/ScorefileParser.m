#import "ScorefileParser.h"

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

static NSString *NoteNameForPitch(NSInteger pitch)
{
    static NSString *names[] = {@"c", @"cs", @"d", @"ds", @"e", @"f", @"fs", @"g", @"gs", @"a", @"as", @"b"};
    NSInteger pc = pitch % 12;
    if (pc < 0) pc += 12;
    NSInteger octave = (pitch / 12) - 1;
    return [NSString stringWithFormat:@"%@%ld", names[pc], (long)octave];
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
    document.title = [path lastPathComponent];
    document.ticksPerQuarter = 480;

    double tempoBPM = 120.0;
    double currentTime = 0.0;
    BOOL inBody = NO;
    NSUInteger trackForPart = 0;
    NSMutableDictionary *partTracks = [NSMutableDictionary dictionary];

    for (NSString *rawStatement in statements) {
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
                    document.tempoMicrosecondsPerQuarter = (NSUInteger)(60000000.0 / tempoBPM);
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
        }

        NSString *event = Trim([statement substringWithRange:NSMakeRange(open.location + 1, close.location - open.location - 1)]);
        NSString *params = [statement substringFromIndex:close.location + 1];
        NSString *pitchString = nil;
        for (NSString *paramName in [NSArray arrayWithObjects:@"keyNum:", @"freq:", nil]) {
            NSRange paramRange = [params rangeOfString:paramName];
            if (paramRange.location != NSNotFound) {
                NSString *after = [params substringFromIndex:paramRange.location + paramRange.length];
                NSScanner *scanner = [NSScanner scannerWithString:after];
                NSString *scanned = nil;
                [scanner scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@" ,\t\r\n"] intoString:&scanned];
                pitchString = scanned;
                break;
            }
        }

        BOOL pitchOK = NO;
        NSInteger pitch = pitchString ? PitchForName(pitchString, &pitchOK) : 60;
        double ticksPerBeat = (double)document.ticksPerQuarter;
        NSUInteger currentTick = (NSUInteger)llround(currentTime * ticksPerBeat);

        if ([event hasPrefix:@"noteOff"]) {
            NSArray *eventParts = [event componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *tag = [eventParts count] > 1 ? [eventParts objectAtIndex:1] : @"0";
            NSString *key = [NSString stringWithFormat:@"%@:%@", partName, tag];
            ScoreNote *note = [activeNotes objectForKey:key];
            if (note && currentTick > note.startTick) {
                note.durationTicks = currentTick - note.startTick;
                if (note.startTick + note.durationTicks > document.totalTicks) {
                    document.totalTicks = note.startTick + note.durationTicks;
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
            if (previous && currentTick > previous.startTick) {
                previous.durationTicks = currentTick - previous.startTick;
            }
            if (pitchOK) {
                ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
                note.pitch = pitch;
                note.channel = 0;
                note.track = [trackNumber integerValue];
                note.startTick = currentTick;
                note.durationTicks = document.ticksPerQuarter;
                [document.notes addObject:note];
                [activeNotes setObject:note forKey:key];
            }
            continue;
        }

        BOOL durationOK = NO;
        double durationSeconds = EvaluateExpression(event, variables, &durationOK);
        if (durationOK && durationSeconds > 0.0 && pitchOK) {
            ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
            note.pitch = pitch;
            note.channel = 0;
            note.track = [trackNumber integerValue];
            note.startTick = currentTick;
            note.durationTicks = MAX((NSUInteger)1, (NSUInteger)llround(durationSeconds * ticksPerBeat));
            [document.notes addObject:note];
            if (note.startTick + note.durationTicks > document.totalTicks) {
                document.totalTicks = note.startTick + note.durationTicks;
            }
        }
    }

    for (ScoreNote *note in [activeNotes allValues]) {
        if (note.durationTicks == 0) {
            note.durationTicks = document.ticksPerQuarter;
        }
        if (note.startTick + note.durationTicks > document.totalTicks) {
            document.totalTicks = note.startTick + note.durationTicks;
        }
    }

    if ([document.notes count] == 0) {
        if (error) *error = ScorefileError(@"No renderable notes were found in the scorefile.");
        return nil;
    }

    [document.notes sortUsingSelector:@selector(compareScoreNote:)];
    return document;
}

+ (BOOL)writeDocument:(ScoreDocument *)document toFileAtPath:(NSString *)path error:(NSError **)error
{
    if (!document) {
        if (error) *error = ScorefileError(@"There is no score to save.");
        return NO;
    }

    double tempoBPM = document.tempoMicrosecondsPerQuarter > 0 ? 60000000.0 / (double)document.tempoMicrosecondsPerQuarter : 120.0;
    NSMutableString *output = [NSMutableString string];
    [output appendString:@"/* Written by ScoreMaker. */\n\n"];
    [output appendFormat:@"info tempo:%.6g;\n", tempoBPM];
    [output appendString:@"part score;\n\nBEGIN;\n\n"];

    NSUInteger lastTick = NSNotFound;
    for (ScoreNote *note in document.notes) {
        if (note.startTick != lastTick) {
            double time = (double)note.startTick / (double)document.ticksPerQuarter;
            [output appendFormat:@"t %.6g;\n", time];
            lastTick = note.startTick;
        }
        double duration = (double)MAX((NSUInteger)1, note.durationTicks) / (double)document.ticksPerQuarter;
        [output appendFormat:@"score (%.6g) keyNum:%@;\n", duration, NoteNameForPitch(note.pitch)];
    }

    [output appendString:@"\nEND;\n"];
    return [output writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error];
}

@end
