#import <Foundation/Foundation.h>
#import "ScorefileParser.h"
#import "MusicXMLParser.h"

static void Require(BOOL condition, NSString *message)
{
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static void CompareNotes(ScoreDocument *left, ScoreDocument *right)
{
    Require([[left notes] count] == [[right notes] count], @"note count changed after round trip");
    for (NSUInteger index = 0; index < [[left notes] count]; index++) {
        ScoreNote *a = [[left notes] objectAtIndex:index];
        ScoreNote *b = [[right notes] objectAtIndex:index];
        Require([a pitch] == [b pitch] && [a track] == [b track] &&
                [a startTick] == [b startTick] && [a durationTicks] == [b durationTicks] &&
                [a isRest] == [b isRest] && [a velocity] == [b velocity],
                @"legacy note data changed after round trip");
    }
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSArray *examples = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"examples" error:NULL];
    for (NSString *name in examples) {
        if (![[name pathExtension] isEqualToString:@"score"]) continue;
        NSError *error = nil;
        ScoreDocument *document = [ScorefileParser parseFileAtPath:[@"examples" stringByAppendingPathComponent:name]
                                                             error:&error];
        Require(document != nil, [NSString stringWithFormat:@"could not parse %@: %@", name, error]);
        Require([[document measures] count] > 0, [NSString stringWithFormat:@"%@ has no synthesized measures", name]);
        for (ScoreNote *note in [document notes]) Require([note voice] == 1, @"legacy note did not default to voice 1");
        NSData *data = [ScorefileParser dataForDocument:document error:&error];
        Require(data != nil, [NSString stringWithFormat:@"could not serialize %@: %@", name, error]);
        NSString *text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
        Require([text rangeOfString:@"ScoreMaker Metadata V1"].location != NSNotFound, @"V1 metadata was removed");
        Require([text rangeOfString:@"ScoreMaker Structure V2"].location != NSNotFound, @"V2 structure metadata is missing");
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
        Require([data writeToFile:path atomically:YES], @"could not write temporary score");
        ScoreDocument *roundTrip = [ScorefileParser parseFileAtPath:path error:&error];
        Require(roundTrip != nil, [NSString stringWithFormat:@"could not reparse %@: %@", name, error]);
        CompareNotes(document, roundTrip);
        Require([[document measures] count] == [[roundTrip measures] count], @"measure count changed after round trip");
    }

    ScoreDocument *voices = [[[ScoreDocument alloc] init] autorelease];
    [voices setTotalTicks:1440];
    ScoreMeasure *pickup = [[[ScoreMeasure alloc] init] autorelease];
    [pickup setNumber:0]; [pickup setStartTick:0]; [pickup setDurationTicks:480];
    [pickup setTimeSignatureNumerator:4]; [pickup setTimeSignatureDenominator:4]; [pickup setImplicit:YES];
    ScoreMeasure *measure = [[[ScoreMeasure alloc] init] autorelease];
    [measure setNumber:1]; [measure setStartTick:480]; [measure setDurationTicks:960];
    [measure setTimeSignatureNumerator:2]; [measure setTimeSignatureDenominator:4];
    [[voices measures] addObjectsFromArray:[NSArray arrayWithObjects:pickup, measure, nil]];
    for (NSInteger voice = 1; voice <= 2; voice++) {
        ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
        [note setPitch:voice == 1 ? 72 : 48]; [note setTrack:0]; [note setChannel:0];
        [note setStartTick:480]; [note setDurationTicks:480]; [note setVoice:voice]; [note setMeasureIndex:1];
        [note setVelocity:voice == 1 ? 96 : 48];
        if (voice == 1) {
            [note setTieStart:YES]; [note setTupletActual:3]; [note setTupletNormal:2];
            [note setDynamic:@"mf"]; [note setArticulation:@"staccato"];
        } else {
            [note setTieEnd:YES];
        }
        [[voices notes] addObject:note];
    }
    [pickup setKeySignatureFifths:2]; [pickup setRepeatStart:YES];
    [measure setKeySignatureFifths:-3]; [measure setRepeatEnd:YES];
    NSError *error = nil;
    NSData *voiceData = [ScorefileParser dataForDocument:voices error:&error];
    NSString *voicePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"scoremaker-voices.score"];
    Require([voiceData writeToFile:voicePath atomically:YES], @"could not write voice test score");
    ScoreDocument *voiceRoundTrip = [ScorefileParser parseFileAtPath:voicePath error:&error];
    Require([[voiceRoundTrip measures] count] == 2, @"explicit measures did not round trip");
    Require([[[voiceRoundTrip notes] objectAtIndex:0] voice] == 1 &&
            [[[voiceRoundTrip notes] objectAtIndex:1] voice] == 2, @"voices did not round trip");
    Require([[[voiceRoundTrip notes] objectAtIndex:0] velocity] == 96 &&
            [[[voiceRoundTrip notes] objectAtIndex:1] velocity] == 48, @"velocities did not round trip");
    Require([[voiceRoundTrip measures][0] keySignatureFifths] == 2 &&
            [[voiceRoundTrip measures][0] repeatStart] && [[voiceRoundTrip measures][1] repeatEnd],
            @"scorefile signatures or repeats did not round trip");
    ScoreNote *scoreFeatureNote = [[voiceRoundTrip notes] objectAtIndex:0];
    Require([scoreFeatureNote tieStart] && [scoreFeatureNote tupletActual] == 3 &&
            [[scoreFeatureNote dynamic] isEqualToString:@"mf"] &&
            [[scoreFeatureNote articulation] isEqualToString:@"staccato"],
            @"scorefile note notation did not round trip");

    NSData *musicXML = [MusicXMLParser dataForDocument:voices error:&error];
    NSString *xmlPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"scoremaker-voices.musicxml"];
    Require([musicXML writeToFile:xmlPath atomically:YES], @"could not write MusicXML voice test");
    ScoreDocument *xmlRoundTrip = [MusicXMLParser parseFileAtPath:xmlPath error:&error];
    Require([[xmlRoundTrip measures] count] == 2, @"MusicXML measures did not round trip");
    Require([[xmlRoundTrip notes] count] == 2, @"MusicXML notes did not round trip");
    Require([[[xmlRoundTrip notes] objectAtIndex:0] voice] == 1 &&
            [[[xmlRoundTrip notes] objectAtIndex:1] voice] == 2, @"MusicXML voices did not round trip");
    Require([[xmlRoundTrip measures][0] keySignatureFifths] == 2 &&
            [[xmlRoundTrip measures][0] repeatStart] && [[xmlRoundTrip measures][1] repeatEnd],
            @"MusicXML signatures or repeats did not round trip");
    ScoreNote *xmlFeatureNote = [[xmlRoundTrip notes] objectAtIndex:0];
    Require([xmlFeatureNote tieStart] && [xmlFeatureNote tupletActual] == 3 &&
            [[xmlFeatureNote dynamic] isEqualToString:@"mf"] &&
            [[xmlFeatureNote articulation] isEqualToString:@"staccato"],
            @"MusicXML note notation did not round trip");

    ScoreDocument *snapshot = [voices copy];
    [[[voices notes] objectAtIndex:0] setPitch:84];
    [[voices measures] removeLastObject];
    Require([[[snapshot notes] objectAtIndex:0] pitch] == 72,
            @"undo snapshot did not deeply copy notes");
    Require([[snapshot measures] count] == 2,
            @"undo snapshot did not deeply copy measures");
    [snapshot release];

    NSLog(@"PASS: .score compatibility and V2 structure round trips");
    [pool drain];
    return 0;
}
