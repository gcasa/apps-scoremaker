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

@implementation MidiParser

+ (ScoreDocument *)parseFileAtPath:(NSString *)path error:(NSError **)error
{
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data) {
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
    document.title = [path lastPathComponent];
    document.ticksPerQuarter = division;

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

    [document.notes sortUsingSelector:@selector(compareScoreNote:)];

    return document;
}

+ (void)parseTrackBytes:(const unsigned char *)bytes
                 length:(NSUInteger)length
             trackIndex:(NSUInteger)trackIndex
               document:(ScoreDocument *)document
{
    NSMutableDictionary *activeNotes = [NSMutableDictionary dictionary];
    NSUInteger offset = 0;
    NSUInteger absoluteTick = 0;
    unsigned char runningStatus = 0;

    while (offset < length) {
        NSUInteger delta = 0;
        if (!ReadVarLen(bytes, length, &offset, &delta)) {
            break;
        }
        absoluteTick += delta;
        if (absoluteTick > document.totalTicks) {
            document.totalTicks = absoluteTick;
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

            if (metaType == 0x51 && metaLength == 3) {
                document.tempoMicrosecondsPerQuarter = ((NSUInteger)bytes[offset] << 16) |
                                                       ((NSUInteger)bytes[offset + 1] << 8) |
                                                       (NSUInteger)bytes[offset + 2];
            } else if (metaType == 0x58 && metaLength >= 2) {
                document.timeSignatureNumerator = bytes[offset];
                document.timeSignatureDenominator = (NSUInteger)1 << bytes[offset + 1];
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

        if (eventType == 0x90 && data2 > 0) {
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
                    note.pitch = data1;
                    note.channel = channel;
                    note.track = trackIndex;
                    note.startTick = startTick;
                    note.durationTicks = absoluteTick - startTick;
                    [document.notes addObject:note];
                }
            }
        }
    }
}

@end
