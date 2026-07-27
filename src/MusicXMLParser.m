#import "MusicXMLParser.h"
#import <math.h>

static NSString * const MusicXMLErrorDomain = @"ScoreMakerMusicXML";

static NSString *EscapeXML(NSString *string)
{
    NSString *escaped = [string stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
    return [escaped stringByReplacingOccurrencesOfString:@"'" withString:@"&apos;"];
}

static NSInteger PitchClassForStep(NSString *step)
{
    if ([step isEqualToString:@"C"]) return 0;
    if ([step isEqualToString:@"D"]) return 2;
    if ([step isEqualToString:@"E"]) return 4;
    if ([step isEqualToString:@"F"]) return 5;
    if ([step isEqualToString:@"G"]) return 7;
    if ([step isEqualToString:@"A"]) return 9;
    return 11;
}

static NSString *StepForPitch(NSInteger pitch, NSInteger accidental)
{
    static NSString *sharpSteps[] = {@"C", @"C", @"D", @"D", @"E", @"F", @"F", @"G", @"G", @"A", @"A", @"B"};
    static NSString *flatSteps[] = {@"C", @"D", @"D", @"E", @"E", @"F", @"G", @"G", @"A", @"A", @"B", @"B"};
    NSInteger pc = pitch % 12;
    if (pc < 0) pc += 12;
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
    BOOL _noteSlurStart;
    BOOL _noteSlurEnd;
    NSString *_noteStep;
    NSInteger _noteAlter;
    NSInteger _noteOctave;
    double _noteDurationQuarters;
    NSString *_scoreTitle;
    NSString *_scoreTitleFontName;
}
- (ScoreDocument *)document;
@end

@implementation MusicXMLImportDelegate

- (id)init
{
    self = [super init];
    if (self) {
        _document = [[ScoreDocument alloc] init];
        [_document setTicksPerQuarter:480];
        _text = [[NSMutableString alloc] init];
        _partNames = [[NSMutableDictionary alloc] init];
        _partPrograms = [[NSMutableDictionary alloc] init];
        _partIndexes = [[NSMutableDictionary alloc] init];
        _divisions = 1;
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
    [_scoreTitle release];
    [_scoreTitleFontName release];
    [super dealloc];
}

- (ScoreDocument *)document
{
    return _document;
}

- (NSUInteger)tickForQuarterPosition:(double)position
{
    return (NSUInteger)MAX((long long)0, llround(position * 480.0));
}

- (void)parser:(NSXMLParser *)parser
 didStartElement:(NSString *)element
    namespaceURI:(NSString *)namespaceURI
   qualifiedName:(NSString *)qualifiedName
      attributes:(NSDictionary *)attributes
{
    (void)parser; (void)namespaceURI; (void)qualifiedName;
    [_text setString:@""];
    if ([element isEqualToString:@"score-part"]) {
        [_currentPartID release];
        _currentPartID = [[attributes objectForKey:@"id"] copy];
    } else if ([element isEqualToString:@"part"]) {
        [_currentPartID release];
        _currentPartID = [[attributes objectForKey:@"id"] copy];
        NSNumber *track = [_partIndexes objectForKey:_currentPartID];
        if (!track) {
            track = [NSNumber numberWithUnsignedInteger:[_partIndexes count]];
            [_partIndexes setObject:track forKey:_currentPartID];
        }
        _currentTrack = [track integerValue];
        _currentQuarter = 0.0;
        _measureStartQuarter = 0.0;
        _measureMaxQuarter = 0.0;
        NSString *name = [_partNames objectForKey:_currentPartID];
        [_document setName:([name length] ? name : [NSString stringWithFormat:@"Part %ld", (long)(_currentTrack + 1)])
                  forTrack:_currentTrack];
        NSNumber *program = [_partPrograms objectForKey:_currentPartID];
        if (program) [_document setProgram:program forTrack:_currentTrack];
    } else if ([element isEqualToString:@"measure"]) {
        _currentQuarter = _measureStartQuarter;
        _measureMaxQuarter = _measureStartQuarter;
        _measureImplicit = [[attributes objectForKey:@"implicit"] isEqualToString:@"yes"];
    } else if ([element isEqualToString:@"note"]) {
        _inNote = YES;
        _noteRest = NO;
        _noteChord = NO;
        _noteGrace = NO;
        _noteSlurStart = NO;
        _noteSlurEnd = NO;
        _noteAlter = 0;
        _noteOctave = 4;
        _noteDurationQuarters = 1.0 / (double)MAX((NSUInteger)1, _divisions);
        [_noteStep release];
        _noteStep = nil;
    } else if (_inNote && [element isEqualToString:@"rest"]) {
        _noteRest = YES;
    } else if (_inNote && [element isEqualToString:@"chord"]) {
        _noteChord = YES;
    } else if (_inNote && [element isEqualToString:@"grace"]) {
        _noteGrace = YES;
        _noteDurationQuarters = 0.0;
    } else if ([element isEqualToString:@"backup"]) {
        _inBackup = YES;
    } else if ([element isEqualToString:@"forward"]) {
        _inForward = YES;
    } else if (_inNote && [element isEqualToString:@"slur"]) {
        NSString *type = [attributes objectForKey:@"type"];
        if ([type isEqualToString:@"start"]) _noteSlurStart = YES;
        if ([type isEqualToString:@"stop"]) _noteSlurEnd = YES;
    } else if ([element isEqualToString:@"sound"]) {
        NSString *tempo = [attributes objectForKey:@"tempo"];
        if (!_foundTempo && [tempo doubleValue] > 0.0) {
            [_document setTempoMicrosecondsPerQuarter:(NSUInteger)llround(60000000.0 / [tempo doubleValue])];
            _foundTempo = YES;
        }
    } else if ([element isEqualToString:@"credit-words"]) {
        NSString *fontFamily = [attributes objectForKey:@"font-family"];
        if ([fontFamily length]) {
            [_scoreTitleFontName release];
            _scoreTitleFontName = [fontFamily copy];
        }
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
    (void)parser; (void)namespaceURI; (void)qualifiedName;
    NSString *value = [_text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([element isEqualToString:@"work-title"] || [element isEqualToString:@"movement-title"]) {
        if ([value length]) {
            [_scoreTitle release];
            _scoreTitle = [value copy];
        }
    } else if ([element isEqualToString:@"part-name"] && _currentPartID) {
        [_partNames setObject:value forKey:_currentPartID];
    } else if ([element isEqualToString:@"midi-program"] && _currentPartID) {
        NSInteger program = MAX((NSInteger)1, MIN((NSInteger)128, [value integerValue])) - 1;
        [_partPrograms setObject:[NSNumber numberWithInteger:program] forKey:_currentPartID];
    } else if ([element isEqualToString:@"per-minute"] && !_foundTempo && [value doubleValue] > 0.0) {
        [_document setTempoMicrosecondsPerQuarter:(NSUInteger)llround(60000000.0 / [value doubleValue])];
        _foundTempo = YES;
    } else if ([element isEqualToString:@"divisions"]) {
        _divisions = MAX((NSUInteger)1, (NSUInteger)[value integerValue]);
    } else if ([element isEqualToString:@"beats"]) {
        [_document setTimeSignatureNumerator:MAX((NSUInteger)1, (NSUInteger)[value integerValue])];
    } else if ([element isEqualToString:@"beat-type"]) {
        [_document setTimeSignatureDenominator:MAX((NSUInteger)1, (NSUInteger)[value integerValue])];
    } else if (_inNote && [element isEqualToString:@"step"]) {
        [_noteStep release];
        _noteStep = [[value uppercaseString] copy];
    } else if (_inNote && [element isEqualToString:@"alter"]) {
        _noteAlter = [value integerValue];
    } else if (_inNote && [element isEqualToString:@"octave"]) {
        _noteOctave = [value integerValue];
    } else if ([element isEqualToString:@"duration"]) {
        double duration = (double)MAX((NSInteger)1, [value integerValue]) /
                          (double)MAX((NSUInteger)1, _divisions);
        if (_inNote) {
            _noteDurationQuarters = duration;
        } else if (_inBackup) {
            _currentQuarter = MAX(_measureStartQuarter, _currentQuarter - duration);
        } else if (_inForward) {
            _currentQuarter += duration;
            _measureMaxQuarter = MAX(_measureMaxQuarter, _currentQuarter);
        }
    } else if ([element isEqualToString:@"note"]) {
        double startQuarter = _noteChord ? _lastNoteStartQuarter : _currentQuarter;
        double endQuarter = startQuarter + _noteDurationQuarters;
        NSUInteger start = [self tickForQuarterPosition:startQuarter];
        NSUInteger end = [self tickForQuarterPosition:endQuarter];
        ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
        [note setRest:_noteRest];
        NSInteger pitch = _noteRest ? 60 : ((_noteOctave + 1) * 12 + PitchClassForStep(_noteStep) + _noteAlter);
        [note setPitch:MIN(MAX(pitch, (NSInteger)0), (NSInteger)127)];
        [note setAccidental:MIN(MAX(_noteAlter, (NSInteger)-1), (NSInteger)1)];
        [note setTrack:_currentTrack];
        [note setChannel:_currentTrack % 16];
        [note setStartTick:start];
        [note setDurationTicks:MAX((NSUInteger)1, end - start)];
        [note setSlurStart:_noteSlurStart];
        [note setSlurEnd:_noteSlurEnd];
        [[_document notes] addObject:note];
        _lastNoteStartQuarter = startQuarter;
        if (!_noteChord && !_noteGrace) _currentQuarter += _noteDurationQuarters;
        _measureMaxQuarter = MAX(_measureMaxQuarter, endQuarter);
        [_document setTotalTicks:MAX([_document totalTicks], end)];
        _inNote = NO;
    } else if ([element isEqualToString:@"backup"]) {
        _inBackup = NO;
    } else if ([element isEqualToString:@"forward"]) {
        _inForward = NO;
    } else if ([element isEqualToString:@"measure"]) {
        double measureQuarters = 4.0 * (double)[_document timeSignatureNumerator] /
                                 (double)MAX((NSUInteger)1, [_document timeSignatureDenominator]);
        double nominalEnd = _measureStartQuarter + measureQuarters;
        // Notes may legitimately sound across a barline. Their end positions must
        // not lengthen a regular measure or every following measure will drift.
        _measureStartQuarter = _measureImplicit ? _measureMaxQuarter : nominalEnd;
        _currentQuarter = _measureStartQuarter;
    }
}

- (void)parserDidEndDocument:(NSXMLParser *)parser
{
    (void)parser;
    if ([_scoreTitle length]) [_document setTitle:_scoreTitle];
    if ([_scoreTitleFontName length]) [_document setTitleFontName:_scoreTitleFontName];
    [[_document notes] sortUsingSelector:@selector(compareScoreNote:)];
}

@end

@implementation MusicXMLParser

+ (ScoreDocument *)parseFileAtPath:(NSString *)path error:(NSError **)error
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        if (error) *error = [NSError errorWithDomain:MusicXMLErrorDomain code:1
                                            userInfo:[NSDictionary dictionaryWithObject:@"The MusicXML file could not be read."
                                                                                 forKey:NSLocalizedDescriptionKey]];
        return nil;
    }
    NSXMLParser *parser = [[[NSXMLParser alloc] initWithData:data] autorelease];
    MusicXMLImportDelegate *delegate = [[[MusicXMLImportDelegate alloc] init] autorelease];
    [parser setDelegate:delegate];
    if (![parser parse]) {
        if (error) *error = [parser parserError];
        return nil;
    }
    return [delegate document];
}

+ (NSData *)dataForDocument:(ScoreDocument *)document error:(NSError **)error
{
    if (!document) {
        if (error) *error = [NSError errorWithDomain:MusicXMLErrorDomain code:2
                                            userInfo:[NSDictionary dictionaryWithObject:@"There is no score to export."
                                                                                 forKey:NSLocalizedDescriptionKey]];
        return nil;
    }
    NSMutableSet *trackSet = [NSMutableSet setWithArray:[[document partNames] allKeys]];
    [trackSet addObjectsFromArray:[[document trackPrograms] allKeys]];
    for (ScoreNote *note in [document notes]) [trackSet addObject:[NSNumber numberWithInteger:[note track]]];
    if ([trackSet count] == 0) [trackSet addObject:[NSNumber numberWithInteger:0]];
    NSArray *tracks = [[trackSet allObjects] sortedArrayUsingSelector:@selector(compare:)];

    NSMutableString *xml = [NSMutableString stringWithString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
    [xml appendString:@"<!DOCTYPE score-partwise PUBLIC \"-//Recordare//DTD MusicXML 4.0 Partwise//EN\" \"http://www.musicxml.org/dtds/partwise.dtd\">\n"];
    [xml appendString:@"<score-partwise version=\"4.0\">\n"];
    [xml appendFormat:@"  <work><work-title>%@</work-title></work>\n", EscapeXML([document title] ?: @"Untitled")];
    if ([[document titleFontName] length] > 0) {
        [xml appendFormat:@"  <credit page=\"1\"><credit-words font-family=\"%@\">%@</credit-words></credit>\n",
                          EscapeXML([document titleFontName]), EscapeXML([document title] ?: @"Untitled")];
    }
    [xml appendString:@"  <part-list>\n"];
    for (NSUInteger i = 0; i < [tracks count]; i++) {
        NSInteger track = [[tracks objectAtIndex:i] integerValue];
        NSString *partID = [NSString stringWithFormat:@"P%lu", (unsigned long)(i + 1)];
        NSString *name = [document nameForTrack:track] ?: [NSString stringWithFormat:@"Part %ld", (long)(track + 1)];
        NSInteger program = [[document programForTrack:track] integerValue];
        [xml appendFormat:@"    <score-part id=\"%@\"><part-name>%@</part-name><midi-instrument id=\"%@-I1\"><midi-channel>%ld</midi-channel><midi-program>%ld</midi-program></midi-instrument></score-part>\n",
                          partID, EscapeXML(name), partID, (long)(track % 16 + 1), (long)(program + 1)];
    }
    [xml appendString:@"  </part-list>\n"];

    NSUInteger tpq = MAX((NSUInteger)1, [document ticksPerQuarter]);
    NSUInteger measureTicks = tpq * 4 * [document timeSignatureNumerator] / MAX((NSUInteger)1, [document timeSignatureDenominator]);
    if (measureTicks == 0) measureTicks = tpq * 4;
    NSUInteger measureCount = MAX((NSUInteger)1, ([document totalTicks] + measureTicks - 1) / measureTicks);
    for (NSUInteger i = 0; i < [tracks count]; i++) {
        NSInteger track = [[tracks objectAtIndex:i] integerValue];
        [xml appendFormat:@"  <part id=\"P%lu\">\n", (unsigned long)(i + 1)];
        for (NSUInteger measure = 0; measure < measureCount; measure++) {
            NSUInteger measureStart = measure * measureTicks;
            NSUInteger measureEnd = measureStart + measureTicks;
            [xml appendFormat:@"    <measure number=\"%lu\">\n", (unsigned long)(measure + 1)];
            if (measure == 0) {
                [xml appendFormat:@"      <attributes><divisions>%lu</divisions><time><beats>%lu</beats><beat-type>%lu</beat-type></time><clef><sign>G</sign><line>2</line></clef></attributes>\n",
                                  (unsigned long)tpq,
                                  (unsigned long)[document timeSignatureNumerator],
                                  (unsigned long)[document timeSignatureDenominator]];
                double bpm = [document tempoMicrosecondsPerQuarter] ? 60000000.0 / [document tempoMicrosecondsPerQuarter] : 120.0;
                [xml appendFormat:@"      <direction placement=\"above\"><sound tempo=\"%.6g\"/></direction>\n", bpm];
            }
            NSInteger cursor = 0;
            for (ScoreNote *note in [document notes]) {
                if ([note track] != track || [note startTick] < measureStart || [note startTick] >= measureEnd) continue;
                NSInteger onset = (NSInteger)([note startTick] - measureStart);
                NSInteger movement = onset - cursor;
                if (movement > 0) [xml appendFormat:@"      <forward><duration>%ld</duration></forward>\n", (long)movement];
                if (movement < 0) [xml appendFormat:@"      <backup><duration>%ld</duration></backup>\n", (long)-movement];
                [xml appendString:@"      <note>"];
                NSInteger accidental = [note accidental];
                if ([note isRest]) {
                    [xml appendString:@"<rest/>"];
                } else {
                    NSInteger naturalPitch = [note pitch] - accidental;
                    NSInteger octave = naturalPitch / 12 - 1;
                    [xml appendFormat:@"<pitch><step>%@</step>", StepForPitch([note pitch], accidental)];
                    if (accidental) [xml appendFormat:@"<alter>%ld</alter>", (long)accidental];
                    [xml appendFormat:@"<octave>%ld</octave></pitch>", (long)octave];
                }
                [xml appendFormat:@"<duration>%lu</duration><voice>%ld</voice>",
                                  (unsigned long)MAX((NSUInteger)1, [note durationTicks]), (long)(track + 1)];
                if (![note isRest] && accidental) {
                    [xml appendFormat:@"<accidental>%@</accidental>", accidental > 0 ? @"sharp" : @"flat"];
                }
                if ([note slurStart] || [note slurEnd]) {
                    [xml appendString:@"<notations>"];
                    if ([note slurStart]) [xml appendString:@"<slur type=\"start\"/>"];
                    if ([note slurEnd]) [xml appendString:@"<slur type=\"stop\"/>"];
                    [xml appendString:@"</notations>"];
                }
                [xml appendString:@"</note>\n"];
                cursor = onset + (NSInteger)[note durationTicks];
            }
            [xml appendString:@"    </measure>\n"];
        }
        [xml appendString:@"  </part>\n"];
    }
    [xml appendString:@"</score-partwise>\n"];
    NSData *data = [xml dataUsingEncoding:NSUTF8StringEncoding];
    if (!data && error) {
        *error = [NSError errorWithDomain:MusicXMLErrorDomain code:3
                                 userInfo:[NSDictionary dictionaryWithObject:@"The MusicXML document could not be encoded."
                                                                      forKey:NSLocalizedDescriptionKey]];
    }
    return data;
}

@end
