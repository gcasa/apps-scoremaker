#import "MidiParser.h"
#import <stdint.h>

static NSString * const MidiParserErrorDomain = @"ScoreMakerMidiParser";

static uint16_t ReadBE16(const unsigned char *bytes, NSUInteger offset)
{
    return (uint16_t)((bytes[offset] << 8) | bytes[offset + 1]);
}

static uint32_t ReadBE32(const unsigned char *bytes, NSUInteger offset)
{
    return ((uint32_t)bytes[offset] << 24) |
           ((uint32_t)bytes[offset + 1] << 16) |
           ((uint32_t)bytes[offset + 2] << 8) |
           (uint32_t)bytes[offset + 3];
}

static BOOL ReadVarLen(const unsigned char *bytes, NSUInteger length, NSUInteger *offset, NSUInteger *value)
{
    NSUInteger result = 0;
    NSUInteger count = 0;
    while (*offset < length && count < 4) {
        unsigned char c = bytes[(*offset)++];
        result = (result << 7) | (NSUInteger)(c & 0x7f);
        count++;
        if ((c & 0x80) == 0) {
            *value = result;
            return YES;
        }
    }
    return NO;
}

static NSError *ParserError(NSString *message)
{
    NSDictionary *info = [NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
    return [NSError errorWithDomain:MidiParserErrorDomain code:1 userInfo:info];
}

static void AppendByte(NSMutableData *data, unsigned char value)
{
    [data appendBytes:&value length:1];
}

static void AppendBE16(NSMutableData *data, uint16_t value)
{
    unsigned char bytes[] = {
        (unsigned char)((value >> 8) & 0xff),
        (unsigned char)(value & 0xff)
    };
    [data appendBytes:bytes length:2];
}

static void AppendBE32(NSMutableData *data, uint32_t value)
{
    unsigned char bytes[] = {
        (unsigned char)((value >> 24) & 0xff),
        (unsigned char)((value >> 16) & 0xff),
        (unsigned char)((value >> 8) & 0xff),
        (unsigned char)(value & 0xff)
    };
    [data appendBytes:bytes length:4];
}

static void AppendVarLen(NSMutableData *data, NSUInteger value)
{
    unsigned char buffer[5];
    NSUInteger count = 0;
    buffer[count++] = (unsigned char)(value & 0x7f);
    while ((value >>= 7) > 0 && count < 5) {
        buffer[count++] = (unsigned char)((value & 0x7f) | 0x80);
    }
    while (count > 0) {
        AppendByte(data, buffer[--count]);
    }
}

static void AppendMetaText(NSMutableData *data, unsigned char type, NSString *text)
{
    NSData *textData = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!textData) {
        textData = [text dataUsingEncoding:NSISOLatin1StringEncoding];
    }
    if (!textData) {
        return;
    }
    AppendByte(data, 0xff);
    AppendByte(data, type);
    AppendVarLen(data, [textData length]);
    [data appendData:textData];
}

static NSComparisonResult CompareMidiEventDictionaries(id a, id b, void *context)
{
    NSUInteger tickA = [[a objectForKey:@"tick"] unsignedIntegerValue];
    NSUInteger tickB = [[b objectForKey:@"tick"] unsignedIntegerValue];
    if (tickA < tickB) return NSOrderedAscending;
    if (tickA > tickB) return NSOrderedDescending;

    NSInteger orderA = [[a objectForKey:@"order"] integerValue];
    NSInteger orderB = [[b objectForKey:@"order"] integerValue];
    if (orderA < orderB) return NSOrderedAscending;
    if (orderA > orderB) return NSOrderedDescending;
    return NSOrderedSame;
}

static NSString *MidiTextFromBytes(const unsigned char *bytes, NSUInteger length)
{
    NSData *data = [NSData dataWithBytes:bytes length:length];
    NSString *text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!text) {
        text = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    }
    return text;
}

static NSString *GeneralMidiProgramName(unsigned char program)
{
    static NSString *names[] = {
        @"Acoustic Grand Piano", @"Bright Acoustic Piano", @"Electric Grand Piano", @"Honky-tonk Piano",
        @"Electric Piano 1", @"Electric Piano 2", @"Harpsichord", @"Clavinet",
        @"Celesta", @"Glockenspiel", @"Music Box", @"Vibraphone",
        @"Marimba", @"Xylophone", @"Tubular Bells", @"Dulcimer",
        @"Drawbar Organ", @"Percussive Organ", @"Rock Organ", @"Church Organ",
        @"Reed Organ", @"Accordion", @"Harmonica", @"Tango Accordion",
        @"Acoustic Guitar Nylon", @"Acoustic Guitar Steel", @"Electric Guitar Jazz", @"Electric Guitar Clean",
        @"Electric Guitar Muted", @"Overdriven Guitar", @"Distortion Guitar", @"Guitar Harmonics",
        @"Acoustic Bass", @"Electric Bass Finger", @"Electric Bass Pick", @"Fretless Bass",
        @"Slap Bass 1", @"Slap Bass 2", @"Synth Bass 1", @"Synth Bass 2",
        @"Violin", @"Viola", @"Cello", @"Contrabass",
        @"Tremolo Strings", @"Pizzicato Strings", @"Orchestral Harp", @"Timpani",
        @"String Ensemble 1", @"String Ensemble 2", @"Synth Strings 1", @"Synth Strings 2",
        @"Choir Aahs", @"Voice Oohs", @"Synth Voice", @"Orchestra Hit",
        @"Trumpet", @"Trombone", @"Tuba", @"Muted Trumpet",
        @"French Horn", @"Brass Section", @"Synth Brass 1", @"Synth Brass 2",
        @"Soprano Sax", @"Alto Sax", @"Tenor Sax", @"Baritone Sax",
        @"Oboe", @"English Horn", @"Bassoon", @"Clarinet",
        @"Piccolo", @"Flute", @"Recorder", @"Pan Flute",
        @"Blown Bottle", @"Shakuhachi", @"Whistle", @"Ocarina",
        @"Lead 1 Square", @"Lead 2 Sawtooth", @"Lead 3 Calliope", @"Lead 4 Chiff",
        @"Lead 5 Charang", @"Lead 6 Voice", @"Lead 7 Fifths", @"Lead 8 Bass Lead",
        @"Pad 1 New Age", @"Pad 2 Warm", @"Pad 3 Polysynth", @"Pad 4 Choir",
        @"Pad 5 Bowed", @"Pad 6 Metallic", @"Pad 7 Halo", @"Pad 8 Sweep",
        @"FX 1 Rain", @"FX 2 Soundtrack", @"FX 3 Crystal", @"FX 4 Atmosphere",
        @"FX 5 Brightness", @"FX 6", @"FX 7 Echoes", @"FX 8 Sci-fi",
        @"Sitar", @"Banjo", @"Shamisen", @"Koto",
        @"Kalimba", @"Bag Pipe", @"Fiddle", @"Shanai",
        @"Tinkle Bell", @"Agogo", @"Steel Drums", @"Woodblock",
        @"Taiko Drum", @"Melodic Tom", @"Synth Drum", @"Reverse Cymbal",
        @"Guitar Fret Noise", @"Breath Noise", @"Seashore", @"Bird Tweet",
        @"Telephone Ring", @"Helicopter", @"Applause", @"Gunshot"
    };
    return names[MIN((NSUInteger)program, (NSUInteger)127)];
}

@implementation MidiParser

+ (ScoreDocument *)parseFileAtPath:(NSString *)path error:(NSError **)error
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        if (error) *error = ParserError(@"The MIDI file could not be read.");
        return nil;
    }

    const unsigned char *bytes = [data bytes];
    NSUInteger length = [data length];
    if (length < 14 || memcmp(bytes, "MThd", 4) != 0) {
        if (error) *error = ParserError(@"The file is not a Standard MIDI file.");
        return nil;
    }

    uint32_t headerLength = ReadBE32(bytes, 4);
    if (headerLength < 6 || 8 + headerLength > length) {
        if (error) *error = ParserError(@"The MIDI header is truncated.");
        return nil;
    }

    uint16_t trackCount = ReadBE16(bytes, 10);
    uint16_t division = ReadBE16(bytes, 12);
    if (division & 0x8000) {
        if (error) *error = ParserError(@"SMPTE time-division MIDI files are not supported.");
        return nil;
    }

    ScoreDocument *document = [[[ScoreDocument alloc] init] autorelease];
    [document setTitle:[[path lastPathComponent] stringByDeletingPathExtension]];
    [document setTicksPerQuarter:division];

    NSUInteger offset = 8 + headerLength;
    for (NSUInteger trackIndex = 0; trackIndex < trackCount && offset + 8 <= length; trackIndex++) {
        if (memcmp(bytes + offset, "MTrk", 4) != 0) {
            if (error) *error = ParserError(@"A MIDI track chunk is missing or malformed.");
            return nil;
        }

        uint32_t trackLength = ReadBE32(bytes, offset + 4);
        offset += 8;
        if (offset + trackLength > length) {
            if (error) *error = ParserError(@"A MIDI track chunk is truncated.");
            return nil;
        }

        [self parseTrackBytes:bytes + offset
                       length:trackLength
                   trackIndex:trackIndex
                     document:document];
        offset += trackLength;
    }

    [[document notes] sortUsingSelector:@selector(compareScoreNote:)];

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

    while (offset < length) {
        NSUInteger delta = 0;
        if (!ReadVarLen(bytes, length, &offset, &delta)) {
            break;
        }
        absoluteTick += delta;
        if (absoluteTick > [document totalTicks]) {
            [document setTotalTicks:absoluteTick];
        }
        if (offset >= length) {
            break;
        }

        unsigned char status = bytes[offset++];
        if (status < 0x80) {
            if (runningStatus == 0) {
                break;
            }
            offset--;
            status = runningStatus;
        } else if (status < 0xf0) {
            runningStatus = status;
        }

        if (status == 0xff) {
            if (offset >= length) break;
            unsigned char metaType = bytes[offset++];
            NSUInteger metaLength = 0;
            if (!ReadVarLen(bytes, length, &offset, &metaLength) || offset + metaLength > length) break;

            if (metaType == 0x03 || metaType == 0x04) {
                NSString *name = MidiTextFromBytes(bytes + offset, metaLength);
                if ([name length] > 0) {
                    [document setName:name forTrack:(NSInteger)trackIndex];
                }
            } else if (metaType == 0x51 && metaLength == 3) {
                [document setTempoMicrosecondsPerQuarter:((NSUInteger)bytes[offset] << 16) |
                                                        ((NSUInteger)bytes[offset + 1] << 8) |
                                                        (NSUInteger)bytes[offset + 2]];
            } else if (metaType == 0x58 && metaLength >= 2) {
                [document setTimeSignatureNumerator:bytes[offset]];
                [document setTimeSignatureDenominator:(NSUInteger)1 << bytes[offset + 1]];
            }

            offset += metaLength;
            runningStatus = 0;
            continue;
        }

        if (status == 0xf0 || status == 0xf7) {
            NSUInteger sysexLength = 0;
            if (!ReadVarLen(bytes, length, &offset, &sysexLength) || offset + sysexLength > length) break;
            offset += sysexLength;
            runningStatus = 0;
            continue;
        }

        unsigned char eventType = status & 0xf0;
        unsigned char channel = status & 0x0f;
        NSUInteger dataLength = (eventType == 0xc0 || eventType == 0xd0) ? 1 : 2;
        if (offset + dataLength > length) {
            break;
        }

        unsigned char data1 = bytes[offset++];
        unsigned char data2 = dataLength == 2 ? bytes[offset++] : 0;

        if (eventType == 0xc0) {
            NSString *name = channel == 9 ? @"Percussion" : GeneralMidiProgramName(data1);
            [channelNames setObject:name forKey:[NSNumber numberWithUnsignedChar:channel]];
            if (![document nameForTrack:(NSInteger)trackIndex]) {
                [document setName:name forTrack:(NSInteger)trackIndex];
            }
        } else if (eventType == 0x90 && data2 > 0) {
            NSString *key = [NSString stringWithFormat:@"%lu:%u:%u", (unsigned long)trackIndex, channel, data1];
            NSMutableArray *starts = [activeNotes objectForKey:key];
            if (!starts) {
                starts = [NSMutableArray array];
                [activeNotes setObject:starts forKey:key];
            }
            [starts addObject:[NSNumber numberWithUnsignedInteger:absoluteTick]];
        } else if (eventType == 0x80 || (eventType == 0x90 && data2 == 0)) {
            NSString *key = [NSString stringWithFormat:@"%lu:%u:%u", (unsigned long)trackIndex, channel, data1];
            NSMutableArray *starts = [activeNotes objectForKey:key];
            if ([starts count] > 0) {
                NSUInteger startTick = [[starts objectAtIndex:0] unsignedIntegerValue];
                [starts removeObjectAtIndex:0];
                if (absoluteTick > startTick) {
                    ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
                    [note setPitch:data1];
                    [note setChannel:channel];
                    [note setTrack:trackIndex];
                    [note setStartTick:startTick];
                    [note setDurationTicks:absoluteTick - startTick];
                    if (![document nameForTrack:(NSInteger)trackIndex]) {
                        NSString *name = [channelNames objectForKey:[NSNumber numberWithUnsignedChar:channel]];
                        if (!name && channel == 9) {
                            name = @"Percussion";
                        }
                        if (name) {
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
    if (!document) {
        if (error) *error = ParserError(@"There is no score to save.");
        return nil;
    }
    if ([document ticksPerQuarter] == 0 || [document ticksPerQuarter] > UINT16_MAX) {
        if (error) *error = ParserError(@"The score uses an unsupported MIDI time division.");
        return nil;
    }

    NSMutableArray *tracks = [NSMutableArray array];
    NSEnumerator *noteEnumerator = [[document notes] objectEnumerator];
    ScoreNote *note = nil;
    while ((note = [noteEnumerator nextObject]) != nil) {
        NSNumber *track = [NSNumber numberWithInteger:[note track]];
        if (![tracks containsObject:track]) {
            [tracks addObject:track];
        }
    }
    if ([tracks count] == 0) {
        [tracks addObject:[NSNumber numberWithInteger:0]];
    }
    [tracks sortUsingSelector:@selector(compare:)];
    if ([tracks count] > UINT16_MAX) {
        if (error) *error = ParserError(@"The score has too many tracks for a Standard MIDI file.");
        return nil;
    }

    NSMutableData *file = [NSMutableData data];
    [file appendBytes:"MThd" length:4];
    AppendBE32(file, 6);
    AppendBE16(file, [tracks count] > 1 ? 1 : 0);
    AppendBE16(file, (uint16_t)[tracks count]);
    AppendBE16(file, (uint16_t)[document ticksPerQuarter]);

    NSEnumerator *trackEnumerator = [tracks objectEnumerator];
    NSNumber *trackNumber = nil;
    BOOL wroteGlobalMetadata = NO;
    while ((trackNumber = [trackEnumerator nextObject]) != nil) {
        NSInteger trackIndex = [trackNumber integerValue];
        NSMutableData *trackData = [NSMutableData data];

        if (!wroteGlobalMetadata) {
            AppendVarLen(trackData, 0);
            AppendByte(trackData, 0xff);
            AppendByte(trackData, 0x51);
            AppendByte(trackData, 3);
            NSUInteger tempo = [document tempoMicrosecondsPerQuarter] > 0 ? [document tempoMicrosecondsPerQuarter] : 500000;
            AppendByte(trackData, (unsigned char)((tempo >> 16) & 0xff));
            AppendByte(trackData, (unsigned char)((tempo >> 8) & 0xff));
            AppendByte(trackData, (unsigned char)(tempo & 0xff));

            AppendVarLen(trackData, 0);
            AppendByte(trackData, 0xff);
            AppendByte(trackData, 0x58);
            AppendByte(trackData, 4);
            AppendByte(trackData, (unsigned char)MIN([document timeSignatureNumerator], (NSUInteger)255));
            NSUInteger denominator = MAX([document timeSignatureDenominator], (NSUInteger)1);
            unsigned char denominatorPower = 0;
            while (denominator > 1 && denominatorPower < 7) {
                denominator >>= 1;
                denominatorPower++;
            }
            AppendByte(trackData, denominatorPower);
            AppendByte(trackData, 24);
            AppendByte(trackData, 8);
            wroteGlobalMetadata = YES;
        }

        NSString *trackName = [document nameForTrack:trackIndex];
        if ([trackName length] > 0) {
            AppendVarLen(trackData, 0);
            AppendMetaText(trackData, 0x03, trackName);
        }

        NSMutableArray *events = [NSMutableArray array];
        noteEnumerator = [[document notes] objectEnumerator];
        while ((note = [noteEnumerator nextObject]) != nil) {
            if ([note track] != trackIndex) {
                continue;
            }
            unsigned char pitch = (unsigned char)MIN(MAX([note pitch], (NSInteger)0), (NSInteger)127);
            unsigned char channel = (unsigned char)MIN(MAX([note channel], (NSInteger)0), (NSInteger)15);
            [events addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                               [NSNumber numberWithUnsignedInteger:[note startTick]], @"tick",
                               [NSNumber numberWithInteger:1], @"order",
                               [NSNumber numberWithUnsignedChar:(unsigned char)(0x90 | channel)], @"status",
                               [NSNumber numberWithUnsignedChar:pitch], @"data1",
                               [NSNumber numberWithUnsignedChar:64], @"data2",
                               nil]];
            [events addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                               [NSNumber numberWithUnsignedInteger:[note startTick] + MAX([note durationTicks], (NSUInteger)1)], @"tick",
                               [NSNumber numberWithInteger:0], @"order",
                               [NSNumber numberWithUnsignedChar:(unsigned char)(0x80 | channel)], @"status",
                               [NSNumber numberWithUnsignedChar:pitch], @"data1",
                               [NSNumber numberWithUnsignedChar:64], @"data2",
                               nil]];
        }
        [events sortUsingFunction:CompareMidiEventDictionaries context:NULL];

        NSUInteger previousTick = 0;
        NSEnumerator *eventEnumerator = [events objectEnumerator];
        NSDictionary *event = nil;
        while ((event = [eventEnumerator nextObject]) != nil) {
            NSUInteger tick = [[event objectForKey:@"tick"] unsignedIntegerValue];
            AppendVarLen(trackData, tick >= previousTick ? tick - previousTick : 0);
            AppendByte(trackData, (unsigned char)[[event objectForKey:@"status"] unsignedCharValue]);
            AppendByte(trackData, (unsigned char)[[event objectForKey:@"data1"] unsignedCharValue]);
            AppendByte(trackData, (unsigned char)[[event objectForKey:@"data2"] unsignedCharValue]);
            previousTick = tick;
        }

        AppendVarLen(trackData, 0);
        AppendByte(trackData, 0xff);
        AppendByte(trackData, 0x2f);
        AppendByte(trackData, 0);

        [file appendBytes:"MTrk" length:4];
        AppendBE32(file, (uint32_t)[trackData length]);
        [file appendData:trackData];
    }

    return file;
}

@end
