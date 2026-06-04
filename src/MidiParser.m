#import "MidiParser.h"

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
    [document setTitle:[path lastPathComponent]];
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

@end
