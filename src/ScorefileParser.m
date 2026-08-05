#import "ScorefileParser.h"
#import <math.h>

static NSString * const ScorefileParserErrorDomain = @"ScoreMakerScorefileParser";
static NSString * const ScoreMakerMetadataMarker = @"ScoreMaker Metadata V1";
static NSString * const ScoreMakerStructureMarker = @"ScoreMaker Structure V2";

static NSError *ScorefileError(NSString *message)
{
    NSDictionary *info = [NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
    return [NSError errorWithDomain:ScorefileParserErrorDomain code:1 userInfo:info];
}

static NSDictionary *ScoreMakerJSONCommentFromScorefile(NSString *input, NSString *marker)
{
    NSRange markerRange = [input rangeOfString:marker];
    if (markerRange.location == NSNotFound) return nil;

    NSUInteger payloadStart = NSMaxRange(markerRange);
    NSRange searchRange = NSMakeRange(payloadStart, [input length] - payloadStart);
    NSRange commentEnd = [input rangeOfString:@"*/" options:0 range:searchRange];
    if (commentEnd.location == NSNotFound) return nil;

    NSString *encoded = [[input substringWithRange:NSMakeRange(payloadStart, commentEnd.location - payloadStart)]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSData *metadataData = [[[NSData alloc] initWithBase64EncodedString:encoded
                                                               options:NSDataBase64DecodingIgnoreUnknownCharacters] autorelease];
    if (!metadataData) return nil;

    id metadata = [NSJSONSerialization JSONObjectWithData:metadataData options:0 error:NULL];
    return [metadata isKindOfClass:[NSDictionary class]] ? metadata : nil;
}

static NSDictionary *ScoreMakerMetadataFromScorefile(NSString *input)
{
    return ScoreMakerJSONCommentFromScorefile(input, ScoreMakerMetadataMarker);
}

static NSString *ScoreMakerMetadataComment(ScoreDocument *document, NSError **error)
{
    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
    if ([[document title] length] > 0) [metadata setObject:[document title] forKey:@"title"];
    if ([[document titleFontName] length] > 0) [metadata setObject:[document titleFontName] forKey:@"titleFont"];
    if ([[document composer] length] > 0) [metadata setObject:[document composer] forKey:@"composer"];
    if ([[document annotationText] length] > 0) [metadata setObject:[document annotationText] forKey:@"annotation"];
    [metadata setObject:[NSNumber numberWithInteger:1] forKey:@"version"];

    NSData *metadataData = [NSJSONSerialization dataWithJSONObject:metadata options:0 error:error];
    if (!metadataData) return nil;
    NSString *encoded = [metadataData base64EncodedStringWithOptions:NSDataBase64Encoding76CharacterLineLength];
    encoded = [encoded stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    return [NSString stringWithFormat:@"/* %@\n%@\n*/\n\n", ScoreMakerMetadataMarker, encoded];
}

static NSString *ScoreMakerStructureComment(ScoreDocument *document, NSError **error)
{
    NSMutableArray *measures = [NSMutableArray array];
    for (ScoreMeasure *measure in [document measures]) {
        [measures addObject:[NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInteger:[measure number]], @"number",
            [NSNumber numberWithUnsignedInteger:[measure startTick]], @"startTick",
            [NSNumber numberWithUnsignedInteger:[measure durationTicks]], @"durationTicks",
            [NSNumber numberWithUnsignedInteger:[measure timeSignatureNumerator]], @"beats",
            [NSNumber numberWithUnsignedInteger:[measure timeSignatureDenominator]], @"beatType",
            [NSNumber numberWithBool:[measure isImplicit]], @"implicit",
            [NSNumber numberWithInteger:[measure keySignatureFifths]], @"keyFifths",
            [NSNumber numberWithBool:[measure repeatStart]], @"repeatStart",
            [NSNumber numberWithBool:[measure repeatEnd]], @"repeatEnd", nil]];
    }
    NSMutableArray *noteDetails = [NSMutableArray array];
    for (ScoreNote *note in [document notes]) {
        NSMutableDictionary *detail = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInteger:[note voice]], @"voice",
            [NSNumber numberWithInteger:[note measureIndex]], @"measureIndex",
            [NSNumber numberWithUnsignedInteger:[note startTick]], @"startTick",
            [NSNumber numberWithUnsignedInteger:[note durationTicks]], @"durationTicks",
            [NSNumber numberWithInteger:[note pitch]], @"pitch",
            [NSNumber numberWithInteger:[note track]], @"track",
            [NSNumber numberWithBool:[note isRest]], @"rest",
            [NSNumber numberWithUnsignedInteger:[note velocity]], @"velocity",
            [NSNumber numberWithBool:[note tieStart]], @"tieStart",
            [NSNumber numberWithBool:[note tieEnd]], @"tieEnd",
            [NSNumber numberWithUnsignedInteger:[note tupletActual]], @"tupletActual",
            [NSNumber numberWithUnsignedInteger:[note tupletNormal]], @"tupletNormal", nil];
        if ([[note dynamic] length]) [detail setObject:[note dynamic] forKey:@"dynamic"];
        if ([[note articulation] length]) [detail setObject:[note articulation] forKey:@"articulation"];
        [noteDetails addObject:detail];
    }
    NSDictionary *structure = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInteger:2], @"version", measures, @"measures",
        noteDetails, @"noteDetails", nil];
    NSData *data = [NSJSONSerialization dataWithJSONObject:structure options:0 error:error];
    if (!data) return nil;
    NSString *encoded = [data base64EncodedStringWithOptions:NSDataBase64Encoding76CharacterLineLength];
    encoded = [encoded stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    return [NSString stringWithFormat:@"/* %@\n%@\n*/\n\n", ScoreMakerStructureMarker, encoded];
}

static void ApplyScoreMakerStructure(ScoreDocument *document, NSDictionary *structure)
{
    NSArray *storedMeasures = [structure objectForKey:@"measures"];
    if ([storedMeasures isKindOfClass:[NSArray class]] && [storedMeasures count] > 0) {
        NSMutableArray *measures = [NSMutableArray array];
        for (NSDictionary *item in storedMeasures) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            ScoreMeasure *measure = [[[ScoreMeasure alloc] init] autorelease];
            [measure setNumber:[[item objectForKey:@"number"] integerValue]];
            [measure setStartTick:[[item objectForKey:@"startTick"] unsignedIntegerValue]];
            [measure setDurationTicks:MAX((NSUInteger)1, [[item objectForKey:@"durationTicks"] unsignedIntegerValue])];
            [measure setTimeSignatureNumerator:MAX((NSUInteger)1, [[item objectForKey:@"beats"] unsignedIntegerValue])];
            [measure setTimeSignatureDenominator:MAX((NSUInteger)1, [[item objectForKey:@"beatType"] unsignedIntegerValue])];
            [measure setImplicit:[[item objectForKey:@"implicit"] boolValue]];
            [measure setKeySignatureFifths:[[item objectForKey:@"keyFifths"] integerValue]];
            [measure setRepeatStart:[[item objectForKey:@"repeatStart"] boolValue]];
            [measure setRepeatEnd:[[item objectForKey:@"repeatEnd"] boolValue]];
            [measures addObject:measure];
        }
        if ([measures count]) [document setMeasures:measures];
    }
    NSArray *details = [structure objectForKey:@"noteDetails"];
    NSMutableSet *assigned = [NSMutableSet set];
    for (NSDictionary *item in details) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        ScoreNote *note = nil;
        for (ScoreNote *candidate in [document notes]) {
            NSValue *identity = [NSValue valueWithPointer:candidate];
            if ([assigned containsObject:identity]) continue;
            if ([candidate startTick] == [[item objectForKey:@"startTick"] unsignedIntegerValue] &&
                [candidate durationTicks] == [[item objectForKey:@"durationTicks"] unsignedIntegerValue] &&
                [candidate pitch] == [[item objectForKey:@"pitch"] integerValue] &&
                [candidate track] == [[item objectForKey:@"track"] integerValue] &&
                [candidate isRest] == [[item objectForKey:@"rest"] boolValue]) {
                note = candidate;
                [assigned addObject:identity];
                break;
            }
        }
        if (!note) continue;
        [note setVoice:[[item objectForKey:@"voice"] integerValue]];
        [note setMeasureIndex:[[item objectForKey:@"measureIndex"] integerValue]];
        NSNumber *velocity = [item objectForKey:@"velocity"];
        if (velocity) [note setVelocity:[velocity unsignedIntegerValue]];
        [note setTieStart:[[item objectForKey:@"tieStart"] boolValue]];
        [note setTieEnd:[[item objectForKey:@"tieEnd"] boolValue]];
        [note setTupletActual:[[item objectForKey:@"tupletActual"] unsignedIntegerValue]];
        [note setTupletNormal:[[item objectForKey:@"tupletNormal"] unsignedIntegerValue]];
        [note setDynamic:[item objectForKey:@"dynamic"]];
        [note setArticulation:[item objectForKey:@"articulation"]];
    }
    [[document notes] sortUsingSelector:@selector(compareScoreNote:)];
}

static NSString *StripComments(NSString *input)
{
    NSMutableString *output = [NSMutableString string];
    NSUInteger length = [input length];
    BOOL inComment = NO;
    BOOL inQuote = NO;
    BOOL escaping = NO;
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [input characterAtIndex:i];
        unichar next = (i + 1 < length) ? [input characterAtIndex:i + 1] : 0;
        if (escaping) {
            [output appendFormat:@"%C", c];
            escaping = NO;
            continue;
        }
        if (!inComment && c == '\\') {
            [output appendFormat:@"%C", c];
            escaping = YES;
            continue;
        }
        if (!inComment && c == '"') {
            inQuote = !inQuote;
            [output appendFormat:@"%C", c];
            continue;
        }
        if (!inQuote && !inComment && c == '/' && next == '*') {
            inComment = YES;
            i++;
            continue;
        }
        if (!inQuote && inComment && c == '*' && next == '/') {
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

static NSArray *ScorefileStatements(NSString *input)
{
    NSMutableArray *statements = [NSMutableArray array];
    NSMutableString *statement = [NSMutableString string];
    BOOL inQuote = NO;
    BOOL escaping = NO;

    for (NSUInteger i = 0; i < [input length]; i++) {
        unichar c = [input characterAtIndex:i];
        if (escaping) {
            [statement appendFormat:@"%C", c];
            escaping = NO;
            continue;
        }
        if (c == '\\') {
            [statement appendFormat:@"%C", c];
            escaping = YES;
            continue;
        }
        if (c == '"') {
            inQuote = !inQuote;
            [statement appendFormat:@"%C", c];
            continue;
        }
        if (c == ';' && !inQuote) {
            [statements addObject:[[statement copy] autorelease]];
            [statement setString:@""];
            continue;
        }
        [statement appendFormat:@"%C", c];
    }

    if ([statement length] > 0) {
        [statements addObject:[[statement copy] autorelease]];
    }
    return statements;
}

static NSString *Trim(NSString *input)
{
    return [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *UnescapeScorefileString(NSString *input)
{
    NSMutableString *output = [NSMutableString string];
    BOOL escaping = NO;
    for (NSUInteger i = 0; i < [input length]; i++) {
        unichar c = [input characterAtIndex:i];
        if (escaping) {
            switch (c) {
                case 'n': [output appendString:@"\n"]; break;
                case 'r': [output appendString:@"\r"]; break;
                case ';': [output appendString:@";"]; break;
                case '"': [output appendString:@"\""]; break;
                case '\\': [output appendString:@"\\"]; break;
                default: [output appendFormat:@"%C", c]; break;
            }
            escaping = NO;
        } else if (c == '\\') {
            escaping = YES;
        } else {
            [output appendFormat:@"%C", c];
        }
    }
    if (escaping) {
        [output appendString:@"\\"];
    }
    return output;
}

static NSString *EscapeScorefileString(NSString *input)
{
    NSString *escaped = [input stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    return [escaped stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
}

static NSString *QuotedStringValue(NSString *statement, NSString *prefix)
{
    if (![statement hasPrefix:prefix]) {
        return nil;
    }
    NSString *value = Trim([statement substringFromIndex:[prefix length]]);
    if ([value hasPrefix:@"\""] && [value hasSuffix:@"\""] && [value length] >= 2) {
        value = [value substringWithRange:NSMakeRange(1, [value length] - 2)];
    }
    return UnescapeScorefileString(value);
}

static NSString *StringVariableValue(NSString *statement, NSString *name)
{
    NSString *prefix = [NSString stringWithFormat:@"string %@", name];
    if ([statement rangeOfString:prefix options:(NSCaseInsensitiveSearch | NSAnchoredSearch)].location == NSNotFound) return nil;
    NSRange equals = [statement rangeOfString:@"="];
    if (equals.location == NSNotFound) return nil;
    NSString *value = Trim([statement substringFromIndex:NSMaxRange(equals)]);
    if (![value hasPrefix:@"\""] || ![value hasSuffix:@"\""] || [value length] < 2) return nil;
    return UnescapeScorefileString([value substringWithRange:NSMakeRange(1, [value length] - 2)]);
}

typedef struct {
    NSString *text;
    NSUInteger index;
    NSDictionary *variables;
    BOOL valid;
} ScorefileExpressionParser;

static void SkipExpressionWhitespace(ScorefileExpressionParser *parser)
{
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    while (parser->index < [parser->text length] &&
           [whitespace characterIsMember:[parser->text characterAtIndex:parser->index]]) {
        parser->index++;
    }
}

static double ParseScorefileExpression(ScorefileExpressionParser *parser);

static double ParseScorefileFactor(ScorefileExpressionParser *parser)
{
    SkipExpressionWhitespace(parser);
    if (parser->index >= [parser->text length]) {
        parser->valid = NO;
        return 0.0;
    }

    unichar c = [parser->text characterAtIndex:parser->index];
    if (c == '+' || c == '-') {
        parser->index++;
        double value = ParseScorefileFactor(parser);
        return c == '-' ? -value : value;
    }
    if (c == '(') {
        parser->index++;
        double value = ParseScorefileExpression(parser);
        SkipExpressionWhitespace(parser);
        if (parser->index >= [parser->text length] ||
            [parser->text characterAtIndex:parser->index] != ')') {
            parser->valid = NO;
            return 0.0;
        }
        parser->index++;
        return value;
    }

    NSUInteger start = parser->index;
    NSCharacterSet *identifierCharacters = [NSCharacterSet characterSetWithCharactersInString:
                                            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789."];
    while (parser->index < [parser->text length] &&
           [identifierCharacters characterIsMember:[parser->text characterAtIndex:parser->index]]) {
        parser->index++;
    }
    if (parser->index == start) {
        parser->valid = NO;
        return 0.0;
    }

    NSString *token = [parser->text substringWithRange:NSMakeRange(start, parser->index - start)];
    NSNumber *variable = [parser->variables objectForKey:token];
    if (variable) return [variable doubleValue];

    NSScanner *scanner = [NSScanner scannerWithString:token];
    double value = 0.0;
    if (![scanner scanDouble:&value] || ![scanner isAtEnd]) {
        parser->valid = NO;
        return 0.0;
    }
    return value;
}

static double ParseScorefileTerm(ScorefileExpressionParser *parser)
{
    double value = ParseScorefileFactor(parser);
    while (parser->valid) {
        SkipExpressionWhitespace(parser);
        if (parser->index >= [parser->text length]) break;
        unichar operation = [parser->text characterAtIndex:parser->index];
        if (operation != '*' && operation != '/') break;
        parser->index++;
        double operand = ParseScorefileFactor(parser);
        if (operation == '*') {
            value *= operand;
        } else if (operand != 0.0) {
            value /= operand;
        } else {
            parser->valid = NO;
        }
    }
    return value;
}

static double ParseScorefileExpression(ScorefileExpressionParser *parser)
{
    double value = ParseScorefileTerm(parser);
    while (parser->valid) {
        SkipExpressionWhitespace(parser);
        if (parser->index >= [parser->text length]) break;
        unichar operation = [parser->text characterAtIndex:parser->index];
        if (operation != '+' && operation != '-') break;
        parser->index++;
        double operand = ParseScorefileTerm(parser);
        value = operation == '+' ? value + operand : value - operand;
    }
    return value;
}

static double EvaluateExpression(NSString *expression, NSDictionary *variables, BOOL *ok)
{
    ScorefileExpressionParser parser = { Trim(expression), 0, variables, YES };
    double value = ParseScorefileExpression(&parser);
    SkipExpressionWhitespace(&parser);
    if (parser.index != [parser.text length]) parser.valid = NO;
    if (ok) *ok = parser.valid;
    return parser.valid ? value : 0.0;
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

static NSInteger AccidentalForName(NSString *value)
{
    NSString *s = [[Trim(value) lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@","]];
    if ([s hasSuffix:@"k"]) {
        s = [s substringToIndex:[s length] - 1];
    }
    if ([s length] < 2) {
        return 0;
    }
    unichar accidental = [s characterAtIndex:1];
    if (accidental == 's' || accidental == '#') return 1;
    if (accidental == 'f' || accidental == 'b') return -1;
    return 0;
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

static NSString *NoteNameForPitch(NSInteger pitch, NSInteger accidental)
{
    static NSString *sharpNames[] = {@"c", @"cs", @"d", @"ds", @"e", @"f", @"fs", @"g", @"gs", @"a", @"as", @"b"};
    static NSString *flatNames[] = {@"c", @"df", @"d", @"ef", @"e", @"f", @"gf", @"g", @"af", @"a", @"bf", @"b"};
    NSInteger pc = pitch % 12;
    if (pc < 0) pc += 12;
    NSInteger octave = (pitch / 12) - 1;
    NSString **names = accidental < 0 ? flatNames : sharpNames;
    return [NSString stringWithFormat:@"%@%ld", names[pc], (long)octave];
}

static BOOL StringContains(NSString *haystack, NSString *needle)
{
    return [haystack rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL StringHasPrefix(NSString *haystack, NSString *prefix)
{
    return [haystack rangeOfString:prefix options:(NSCaseInsensitiveSearch | NSAnchoredSearch)].location != NSNotFound;
}

static BOOL IsPercussionDescriptor(NSString *value)
{
    NSString *s = Trim(value);
    return StringContains(s, @"percussion") || StringContains(s, @"drum");
}

static NSNumber *GeneralMidiProgramForDescriptor(NSString *value)
{
    NSString *s = [Trim(value) stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"'"]];
    if ([s length] == 0) {
        return nil;
    }

    NSScanner *numberScanner = [NSScanner scannerWithString:s];
    NSInteger numericProgram = -1;
    if ([numberScanner scanInteger:&numericProgram] && [numberScanner isAtEnd]) {
        if (numericProgram >= 0 && numericProgram <= 127) {
            return [NSNumber numberWithInteger:numericProgram];
        }
        if (numericProgram >= 1 && numericProgram <= 128) {
            return [NSNumber numberWithInteger:numericProgram - 1];
        }
    }

    if (StringContains(s, @"honky")) return [NSNumber numberWithInteger:3];
    if (StringContains(s, @"bright") && StringContains(s, @"piano")) return [NSNumber numberWithInteger:1];
    if ((StringContains(s, @"electric") || StringContains(s, @"rhodes")) && StringContains(s, @"piano")) return [NSNumber numberWithInteger:4];
    if (StringContains(s, @"harpsichord")) return [NSNumber numberWithInteger:6];
    if (StringContains(s, @"clav")) return [NSNumber numberWithInteger:7];
    if (StringContains(s, @"piano")) return [NSNumber numberWithInteger:0];

    if (StringContains(s, @"glockenspiel")) return [NSNumber numberWithInteger:9];
    if (StringContains(s, @"vibraphone")) return [NSNumber numberWithInteger:11];
    if (StringContains(s, @"marimba")) return [NSNumber numberWithInteger:12];
    if (StringContains(s, @"xylophone")) return [NSNumber numberWithInteger:13];
    if (StringContains(s, @"bells")) return [NSNumber numberWithInteger:14];

    if (StringContains(s, @"church") && StringContains(s, @"organ")) return [NSNumber numberWithInteger:19];
    if (StringContains(s, @"organ")) return [NSNumber numberWithInteger:16];
    if (StringContains(s, @"accordion")) return [NSNumber numberWithInteger:21];
    if (StringContains(s, @"harmonica")) return [NSNumber numberWithInteger:22];

    if (StringContains(s, @"nylon") && StringContains(s, @"guitar")) return [NSNumber numberWithInteger:24];
    if (StringContains(s, @"steel") && StringContains(s, @"guitar")) return [NSNumber numberWithInteger:25];
    if (StringContains(s, @"distortion") && StringContains(s, @"guitar")) return [NSNumber numberWithInteger:30];
    if (StringContains(s, @"overdriven") && StringContains(s, @"guitar")) return [NSNumber numberWithInteger:29];
    if (StringContains(s, @"electric") && StringContains(s, @"guitar")) return [NSNumber numberWithInteger:27];
    if (StringContains(s, @"pluck")) return [NSNumber numberWithInteger:24];
    if (StringContains(s, @"guitar")) return [NSNumber numberWithInteger:24];

    if (StringContains(s, @"contrabass") || StringContains(s, @"double bass")) return [NSNumber numberWithInteger:43];
    if (StringContains(s, @"electric") && StringContains(s, @"bass")) return [NSNumber numberWithInteger:33];
    if (StringContains(s, @"bass guitar")) return [NSNumber numberWithInteger:33];
    if (StringContains(s, @"fretless")) return [NSNumber numberWithInteger:35];
    if (StringContains(s, @"bassoon")) return [NSNumber numberWithInteger:70];
    if (StringContains(s, @"bass")) return [NSNumber numberWithInteger:32];

    if (StringContains(s, @"violin")) return [NSNumber numberWithInteger:40];
    if (StringContains(s, @"viola")) return [NSNumber numberWithInteger:41];
    if (StringContains(s, @"cello")) return [NSNumber numberWithInteger:42];
    if (StringContains(s, @"harp")) return [NSNumber numberWithInteger:46];
    if (StringContains(s, @"timpani")) return [NSNumber numberWithInteger:47];
    if (StringContains(s, @"pizzicato")) return [NSNumber numberWithInteger:45];
    if (StringContains(s, @"strings") || StringContains(s, @"string")) return [NSNumber numberWithInteger:48];

    if (StringContains(s, @"choir")) return [NSNumber numberWithInteger:52];
    if (StringContains(s, @"voice") || StringContains(s, @"vocal")) return [NSNumber numberWithInteger:53];

    if (StringContains(s, @"trumpet")) return [NSNumber numberWithInteger:56];
    if (StringContains(s, @"trombone")) return [NSNumber numberWithInteger:57];
    if (StringContains(s, @"tuba")) return [NSNumber numberWithInteger:58];
    if (StringContains(s, @"horn")) return [NSNumber numberWithInteger:60];
    if (StringContains(s, @"brass")) return [NSNumber numberWithInteger:61];

    if (StringContains(s, @"soprano sax")) return [NSNumber numberWithInteger:64];
    if (StringContains(s, @"alto sax")) return [NSNumber numberWithInteger:65];
    if (StringContains(s, @"tenor sax")) return [NSNumber numberWithInteger:66];
    if (StringContains(s, @"baritone sax")) return [NSNumber numberWithInteger:67];
    if (StringContains(s, @"sax")) return [NSNumber numberWithInteger:65];
    if (StringContains(s, @"oboe")) return [NSNumber numberWithInteger:68];
    if (StringContains(s, @"english horn")) return [NSNumber numberWithInteger:69];
    if (StringContains(s, @"clarinet")) return [NSNumber numberWithInteger:71];
    if (StringContains(s, @"piccolo")) return [NSNumber numberWithInteger:72];
    if (StringContains(s, @"flute")) return [NSNumber numberWithInteger:73];
    if (StringContains(s, @"recorder")) return [NSNumber numberWithInteger:74];

    return nil;
}

static NSString *ScorefileParameterValue(NSString *params, NSString *name)
{
    NSString *prefix = [name stringByAppendingString:@":"];
    NSRange range = [params rangeOfString:prefix options:NSCaseInsensitiveSearch];
    if (range.location == NSNotFound) {
        return nil;
    }

    NSUInteger index = range.location + range.length;
    while (index < [params length] &&
           [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[params characterAtIndex:index]]) {
        index++;
    }
    if (index >= [params length]) {
        return nil;
    }

    if ([params characterAtIndex:index] == '"') {
        NSMutableString *quoted = [NSMutableString string];
        BOOL escaping = NO;
        index++;
        while (index < [params length]) {
            unichar c = [params characterAtIndex:index++];
            if (escaping) {
                [quoted appendFormat:@"%C", c];
                escaping = NO;
            } else if (c == '\\') {
                escaping = YES;
            } else if (c == '"') {
                break;
            } else {
                [quoted appendFormat:@"%C", c];
            }
        }
        return quoted;
    }

    NSCharacterSet *stopSet = [NSCharacterSet characterSetWithCharactersInString:@" ,;\t\r\n"];
    NSMutableString *value = [NSMutableString string];
    while (index < [params length]) {
        unichar c = [params characterAtIndex:index];
        if ([stopSet characterIsMember:c]) {
            break;
        }
        [value appendFormat:@"%C", c];
        index++;
    }
    return [value length] > 0 ? value : nil;
}

static NSString *InstrumentDescriptorInParameters(NSString *params)
{
    NSArray *names = [NSArray arrayWithObjects:@"instrument", @"sound", @"synthPatch", @"patch", @"preset", @"program", @"gmProgram", nil];
    NSEnumerator *enumerator = [names objectEnumerator];
    NSString *name = nil;
    while ((name = [enumerator nextObject]) != nil) {
        NSString *value = ScorefileParameterValue(params, name);
        if ([value length] > 0) {
            return value;
        }
    }
    return nil;
}

static NSInteger MidiChannelForScorefileTrack(NSInteger track, NSString *descriptor)
{
    if (descriptor && IsPercussionDescriptor(descriptor)) {
        return 9;
    }
    NSInteger channel = track % 15;
    if (channel >= 9) {
        channel++;
    }
    return channel;
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
    NSArray *statements = ScorefileStatements(content);
    NSMutableDictionary *variables = [NSMutableDictionary dictionary];
    NSMutableDictionary *activeNotes = [NSMutableDictionary dictionary];
    ScoreDocument *document = [[[ScoreDocument alloc] init] autorelease];
    [document setTitle:[[path lastPathComponent] stringByDeletingPathExtension]];
    [document setTicksPerQuarter:480];
    NSDictionary *metadata = ScoreMakerMetadataFromScorefile(raw);
    NSDictionary *structure = ScoreMakerJSONCommentFromScorefile(raw, ScoreMakerStructureMarker);
    NSString *metadataTitle = [metadata objectForKey:@"title"];
    NSString *metadataTitleFont = [metadata objectForKey:@"titleFont"];
    NSString *metadataComposer = [metadata objectForKey:@"composer"];
    NSString *metadataAnnotation = [metadata objectForKey:@"annotation"];
    if ([metadataTitle isKindOfClass:[NSString class]]) [document setTitle:metadataTitle];
    if ([metadataTitleFont isKindOfClass:[NSString class]]) [document setTitleFontName:metadataTitleFont];
    if ([metadataComposer isKindOfClass:[NSString class]]) [document setComposer:metadataComposer];
    if ([metadataAnnotation isKindOfClass:[NSString class]]) [document setAnnotationText:metadataAnnotation];

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
        NSString *scoreTitle = StringVariableValue(statement, @"scoreTitle");
        if (scoreTitle) {
            [document setTitle:scoreTitle];
            continue;
        }
        NSString *scoreComposer = StringVariableValue(statement, @"scoreComposer");
        if (scoreComposer) {
            [document setComposer:scoreComposer];
            continue;
        }
        NSString *scoreAnnotation = StringVariableValue(statement, @"scoreAnnotation");
        if (scoreAnnotation) {
            [document setAnnotationText:scoreAnnotation];
            continue;
        }
        NSString *annotation = QuotedStringValue(statement, @"annotation ");
        if (annotation) {
            [document setAnnotationText:annotation];
            continue;
        }
        NSString *composer = QuotedStringValue(statement, @"composer ");
        if (!composer) composer = QuotedStringValue(statement, @"author ");
        if (composer) {
            [document setComposer:composer];
            continue;
        }
        NSString *titleFont = QuotedStringValue(statement, @"titleFont ");
        if (titleFont) {
            [document setTitleFontName:titleFont];
            continue;
        }
        NSString *title = QuotedStringValue(statement, @"title ");
        if (title) {
            [document setTitle:title];
            continue;
        }
        if ([statement rangeOfString:@"BEGIN" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            inBody = YES;
            continue;
        }
        if ([statement rangeOfString:@"END" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            break;
        }

        if (StringHasPrefix(statement, @"info ")) {
            NSRange tempoRange = [statement rangeOfString:@"tempo:" options:NSCaseInsensitiveSearch];
            if (tempoRange.location != NSNotFound) {
                NSString *tempoString = [statement substringFromIndex:tempoRange.location + tempoRange.length];
                NSScanner *scanner = [NSScanner scannerWithString:tempoString];
                double scannedTempo = 0.0;
                if ([scanner scanDouble:&scannedTempo] && scannedTempo > 0.0) {
                    tempoBPM = scannedTempo;
                    [document setTempoMicrosecondsPerQuarter:(NSUInteger)(60000000.0 / tempoBPM)];
                }
            }
            NSRange timingRange = [statement rangeOfString:@"timeSignature:" options:NSCaseInsensitiveSearch];
            if (timingRange.location != NSNotFound) {
                NSString *timingString = [statement substringFromIndex:timingRange.location + timingRange.length];
                NSScanner *scanner = [NSScanner scannerWithString:timingString];
                NSInteger numerator = 0;
                NSInteger denominator = 0;
                NSString *slash = nil;
                if ([scanner scanInteger:&numerator] &&
                    [scanner scanString:@"/" intoString:&slash] &&
                    [scanner scanInteger:&denominator] &&
                    numerator > 0 &&
                    denominator > 0) {
                    [document setTimeSignatureNumerator:(NSUInteger)numerator];
                    [document setTimeSignatureDenominator:(NSUInteger)denominator];
                }
            }
            continue;
        }

        if (StringHasPrefix(statement, @"var ")) {
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

        if (!inBody && StringHasPrefix(statement, @"part ")) {
            NSString *partDeclaration = Trim([statement substringFromIndex:5]);
            NSArray *partNames = [partDeclaration componentsSeparatedByString:@","];
            NSEnumerator *partNameEnumerator = [partNames objectEnumerator];
            NSString *rawPartName = nil;
            while ((rawPartName = [partNameEnumerator nextObject]) != nil) {
                NSString *partName = Trim(rawPartName);
                NSArray *partTokens = [partName componentsSeparatedByCharactersInSet:
                                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                partName = [partTokens count] > 0 ? [partTokens objectAtIndex:0] : @"part";
                if ([partName length] == 0 || [partTracks objectForKey:partName]) continue;
                NSNumber *trackNumber = [NSNumber numberWithUnsignedInteger:trackForPart++];
                [partTracks setObject:trackNumber forKey:partName];
                [document setName:partName forTrack:[trackNumber integerValue]];
                NSNumber *program = GeneralMidiProgramForDescriptor(partName);
                if (program) {
                    [document setProgram:program forTrack:[trackNumber integerValue]];
                }
            }
            continue;
        }

        if (!inBody) {
            NSArray *partInfoTokens = [statement componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *partName = [partInfoTokens count] > 0 ? [partInfoTokens objectAtIndex:0] : nil;
            NSNumber *trackNumber = partName ? [partTracks objectForKey:partName] : nil;
            if (trackNumber) {
                NSString *instrumentDescriptor = InstrumentDescriptorInParameters(statement);
                NSNumber *program = instrumentDescriptor ? GeneralMidiProgramForDescriptor(instrumentDescriptor) : nil;
                if (program) {
                    [document setProgram:program forTrack:[trackNumber integerValue]];
                }
            }
            continue;
        }

        if (StringHasPrefix(statement, @"t ")) {
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
            NSNumber *program = GeneralMidiProgramForDescriptor(partName);
            if (program) {
                [document setProgram:program forTrack:[trackNumber integerValue]];
            }
        }

        NSString *event = Trim([statement substringWithRange:NSMakeRange(open.location + 1, close.location - open.location - 1)]);
        NSString *params = [statement substringFromIndex:close.location + 1];
        NSString *instrumentDescriptor = InstrumentDescriptorInParameters(params);
        if ([instrumentDescriptor length] > 0) {
            NSNumber *program = GeneralMidiProgramForDescriptor(instrumentDescriptor);
            if (program) {
                [document setProgram:program forTrack:[trackNumber integerValue]];
            }
        }
        NSString *channelDescriptor = instrumentDescriptor ? instrumentDescriptor : [document nameForTrack:[trackNumber integerValue]];
        NSInteger scorefileChannel = MidiChannelForScorefileTrack([trackNumber integerValue], channelDescriptor);
        NSString *pitchString = nil;
        BOOL pitchIsFrequency = NO;
        NSRange keyNumRange = [params rangeOfString:@"keyNum:" options:NSCaseInsensitiveSearch];
        NSRange freqRange = [params rangeOfString:@"freq:" options:NSCaseInsensitiveSearch];
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

        if (StringHasPrefix(event, @"noteOff")) {
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

        if (StringHasPrefix(event, @"noteOn") || (StringHasPrefix(event, @"noteUpdate") && pitchOK)) {
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
                [note setAccidental:AccidentalForName(pitchString)];
                [note setChannel:scorefileChannel];
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
        if (durationOK && durationSeconds > 0.0 && (pitchOK || !pitchString)) {
            ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
            [note setRest:!pitchOK];
            [note setPitch:pitchOK ? pitch : 60];
            if (pitchOK && !pitchIsFrequency) {
                [note setAccidental:AccidentalForName(pitchString)];
            }
            [note setChannel:scorefileChannel];
            [note setTrack:[trackNumber integerValue]];
            [note setStartTick:currentTick];
            [note setDurationTicks:MAX((NSUInteger)1, (NSUInteger)llround(durationSeconds * ticksPerBeat))];
            [note setSlurStart:([params rangeOfString:@"slurStart:1" options:NSCaseInsensitiveSearch].location != NSNotFound)];
            [note setSlurEnd:([params rangeOfString:@"slurStop:1" options:NSCaseInsensitiveSearch].location != NSNotFound)];
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
    if (structure) {
        ApplyScoreMakerStructure(document, structure);
    } else {
        [document buildDefaultMeasures];
    }
    return document;
}

+ (BOOL)writeDocument:(ScoreDocument *)document toFileAtPath:(NSString *)path error:(NSError **)error
{
    NSData *data = [self dataForDocument:document error:error];
    if (!data) {
        return NO;
    }
    return [data writeToFile:path options:NSDataWritingAtomic error:error];
}

+ (NSData *)dataForDocument:(ScoreDocument *)document error:(NSError **)error
{
    if (!document) {
        if (error) *error = ScorefileError(@"There is no score to save.");
        return nil;
    }

    double tempoBPM = [document tempoMicrosecondsPerQuarter] > 0 ? 60000000.0 / (double)[document tempoMicrosecondsPerQuarter] : 120.0;
    NSMutableString *output = [NSMutableString string];
    [output appendString:@"/* Written by ScoreMaker. */\n\n"];
    NSString *metadataComment = ScoreMakerMetadataComment(document, error);
    if (!metadataComment) return nil;
    [output appendString:metadataComment];
    if ([[document measures] count] == 0) [document buildDefaultMeasures];
    NSString *structureComment = ScoreMakerStructureComment(document, error);
    if (!structureComment) return nil;
    [output appendString:structureComment];
    if ([[document title] length] > 0) {
        [output appendFormat:@"string scoreTitle = \"%@\";\n", EscapeScorefileString([document title])];
    }
    if ([[document composer] length] > 0) {
        [output appendFormat:@"string scoreComposer = \"%@\";\n", EscapeScorefileString([document composer])];
    }
    if ([[document annotationText] length] > 0) {
        [output appendFormat:@"string scoreAnnotation = \"%@\";\n", EscapeScorefileString([document annotationText])];
    }
    [output appendFormat:@"info tempo:%.6g timeSignature:%lu/%lu;\n",
                         tempoBPM,
                         (unsigned long)[document timeSignatureNumerator],
                         (unsigned long)[document timeSignatureDenominator]];
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
    NSEnumerator *definedTrackEnumerator = [[[document partNames] allKeys] objectEnumerator];
    NSNumber *definedTrack = nil;
    while ((definedTrack = [definedTrackEnumerator nextObject]) != nil) {
        if (![tracks containsObject:definedTrack]) [tracks addObject:definedTrack];
    }
    definedTrackEnumerator = [[[document trackPrograms] allKeys] objectEnumerator];
    while ((definedTrack = [definedTrackEnumerator nextObject]) != nil) {
        if (![tracks containsObject:definedTrack]) [tracks addObject:definedTrack];
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
        NSNumber *program = [document programForTrack:[track integerValue]];
        [output appendFormat:@"part %@;\n", identifier];
        if (program) [output appendFormat:@"%@ program:%ld;\n", identifier, (long)[program integerValue]];
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
        if ([note isRest]) {
            [output appendFormat:@"%@ (%.6g);\n", identifier, duration];
        } else {
            [output appendFormat:@"%@ (%.6g) keyNum:%@k%@%@;\n",
                                 identifier,
                                 duration,
                                 NoteNameForPitch([note pitch], [note accidental]),
                                 [note slurStart] ? @" slurStart:1" : @"",
                                 [note slurEnd] ? @" slurStop:1" : @""];
        }
    }

    [output appendString:@"\nEND;\n"];
    NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
    if (!data && error) {
        *error = ScorefileError(@"The scorefile could not be encoded as UTF-8.");
    }
    return data;
}

@end
