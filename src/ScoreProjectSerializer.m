/*
 * Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 *
 * This file is part of ScoreMaker.
 * ScoreMaker is distributed under the GNU Lesser General Public License 2.1 or later.
 */

#import "ScoreProjectSerializer.h"
#import "MusicPlatformModel.h"
#import "ScorefileParser.h"

static NSString *const ScoreProjectErrorDomain = @"ScoreMakerProject";

static NSDictionary *
ScoreProjectSchemas (void)
{
  static NSDictionary *schemas = nil;
  if (!schemas)
    schemas = [[NSDictionary alloc]
      initWithObjectsAndKeys:@[
        @"identifier", @"name", @"backendIdentifier", @"program", @"transposition", @"lowestPitch",
        @"highestPitch", @"parameters"
      ],
                             @"ScoreInstrumentDefinition",
                             @[ @"identifier", @"number", @"preferredStemDirection" ],
                             @"ScoreVoiceDefinition", @[ @"identifier", @"clef", @"voices" ],
                             @"ScoreStaffDefinition",
                             @[
                               @"identifier", @"name", @"abbreviatedName", @"legacyTrack",
                               @"visible", @"midiOutputUniqueID", @"midiOutputName",
                               @"midiFallbackMode", @"midiFallbackUniqueID", @"midiFallbackName",
                               @"instrument", @"staves", @"synthesisGraph"
                             ],
                             @"ScorePartDefinition", @[ @"tick", @"microsecondsPerQuarter" ],
                             @"ScoreTempoEvent",
                             @[
                               @"identifier", @"sourceIdentifier", @"sourceChannel",
                               @"destinationPartIdentifier", @"destinationChannel",
                               @"transposition", @"velocityScale", @"enabled"
                             ],
                             @"ScoreMIDIRoute",
                             @[ @"identifier", @"typeIdentifier", @"parameters" ],
                             @"ScoreSynthesisNode",
                             @[
                               @"sourceNodeIdentifier", @"sourcePort", @"destinationNodeIdentifier",
                               @"destinationPort"
                             ],
                             @"ScoreSynthesisConnection", @[ @"nodes", @"connections" ],
                             @"ScoreSynthesisGraph", @[ @"source", @"diagnostics" ],
                             @"ScoreCompositionProgram", nil];
  return schemas;
}

static id ScoreProjectEncode (id object);
static id
ScoreProjectEncode (id object)
{
  if (!object || object == [NSNull null])
    return [NSNull null];
  if ([object isKindOfClass:[NSString class]] || [object isKindOfClass:[NSNumber class]])
    return object;
  if ([object isKindOfClass:[NSData class]])
    return [NSDictionary dictionaryWithObjectsAndKeys:@"NSData", @"type",
                                                      [object base64EncodedStringWithOptions:0],
                                                      @"base64", nil];
  if ([object isKindOfClass:[NSArray class]])
    {
      NSMutableArray *items = [NSMutableArray array];
      for (id item in object)
        [items addObject:ScoreProjectEncode (item)];
      return items;
    }
  if ([object isKindOfClass:[NSDictionary class]])
    {
      NSMutableDictionary *items = [NSMutableDictionary dictionary];
      for (id key in object)
        [items setObject:ScoreProjectEncode ([object objectForKey:key]) forKey:key];
      return items;
    }
  NSString *type = NSStringFromClass ([object class]);
  NSArray *keys = [ScoreProjectSchemas () objectForKey:type];
  if (!keys)
    return [NSNull null];
  NSMutableDictionary *encoded = [NSMutableDictionary dictionaryWithObject:type forKey:@"type"];
  for (NSString *key in keys)
    {
      id value = [object valueForKey:key];
      if (value)
        [encoded setObject:ScoreProjectEncode (value) forKey:key];
    }
  return encoded;
}

static id ScoreProjectDecode (id encoded);
static id
ScoreProjectDecode (id encoded)
{
  if (!encoded || encoded == [NSNull null])
    return nil;
  if ([encoded isKindOfClass:[NSString class]] || [encoded isKindOfClass:[NSNumber class]])
    return encoded;
  if ([encoded isKindOfClass:[NSArray class]])
    {
      NSMutableArray *items = [NSMutableArray array];
      for (id item in encoded)
        {
          id value = ScoreProjectDecode (item);
          if (value)
            [items addObject:value];
        }
      return items;
    }
  if (![encoded isKindOfClass:[NSDictionary class]])
    return nil;
  NSString *type = [encoded objectForKey:@"type"];
  if ([type isEqualToString:@"NSData"])
    return [[[NSData alloc] initWithBase64EncodedString:[encoded objectForKey:@"base64"]
                                                options:0] autorelease];
  if (!type || ![ScoreProjectSchemas () objectForKey:type])
    {
      NSMutableDictionary *items = [NSMutableDictionary dictionary];
      for (id key in encoded)
        {
          id value = ScoreProjectDecode ([encoded objectForKey:key]);
          if (value)
            [items setObject:value forKey:key];
        }
      return items;
    }
  NSArray *keys = [ScoreProjectSchemas () objectForKey:type];
  Class class = NSClassFromString (type);
  if (!class || !keys)
    return nil;
  id object = [[[class alloc] init] autorelease];
  for (NSString *key in keys)
    {
      id value = ScoreProjectDecode ([encoded objectForKey:key]);
      if (value)
        [object setValue:value forKey:key];
    }
  return object;
}

@implementation ScoreProjectSerializer
+ (NSData *)dataForDocument:(ScoreDocument *)document error:(NSError **)error
{
  NSData *scoreData = [ScorefileParser dataForDocument:document error:error];
  if (!scoreData)
    return nil;
  NSDictionary *platform = [NSDictionary
    dictionaryWithObjectsAndKeys:ScoreProjectEncode ([document parts]), @"parts",
                                 ScoreProjectEncode ([document tempoEvents]), @"tempoEvents",
                                 ScoreProjectEncode ([document midiRoutes]), @"midiRoutes",
                                 ScoreProjectEncode ([document synthesisGraph]), @"synthesisGraph",
                                 ScoreProjectEncode ([document compositionProgram]),
                                 @"compositionProgram", nil];
  NSDictionary *project = [NSDictionary
    dictionaryWithObjectsAndKeys:@2, @"version", [scoreData base64EncodedStringWithOptions:0],
                                 @"scorefile",
                                 [NSNumber numberWithUnsignedInteger:[scoreData length]],
                                 @"scorefileLength", platform, @"platform", nil];
  return [NSJSONSerialization dataWithJSONObject:project options:0 error:error];
}

+ (ScoreDocument *)documentFromData:(NSData *)data error:(NSError **)error
{
  NSDictionary *project = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
  NSInteger version = [[project objectForKey:@"version"] integerValue];
  if (![project isKindOfClass:[NSDictionary class]] || version < 1 || version > 2
      || ![[project objectForKey:@"scorefile"] isKindOfClass:[NSString class]])
    {
      if (error)
        *error = [NSError
          errorWithDomain:ScoreProjectErrorDomain
                     code:1
                 userInfo:@{ NSLocalizedDescriptionKey : @"Unsupported ScoreMaker project." }];
      return nil;
    }
  NSData *scoreData =
    [[[NSData alloc] initWithBase64EncodedString:[project objectForKey:@"scorefile"]
                                         options:0] autorelease];
  if (!scoreData
      || (version >= 2 &&
          [scoreData length] != [[project objectForKey:@"scorefileLength"] unsignedIntegerValue]))
    {
      if (error)
        *error = [NSError
          errorWithDomain:ScoreProjectErrorDomain
                     code:2
                 userInfo:@{ NSLocalizedDescriptionKey : @"The project score data is damaged." }];
      return nil;
    }
  NSString *path = [NSTemporaryDirectory ()
    stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  if (![scoreData writeToFile:path options:NSDataWritingAtomic error:error])
    return nil;
  ScoreDocument *document = [ScorefileParser parseFileAtPath:path error:error];
  [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
  if (!document)
    return nil;
  NSDictionary *platform = [project objectForKey:@"platform"];
  id value = ScoreProjectDecode ([platform objectForKey:@"parts"]);
  if (value)
    [document setParts:value];
  value = ScoreProjectDecode ([platform objectForKey:@"tempoEvents"]);
  if (value)
    [document setTempoEvents:value];
  value = ScoreProjectDecode ([platform objectForKey:@"midiRoutes"]);
  if (value)
    [document setMidiRoutes:value];
  value = ScoreProjectDecode ([platform objectForKey:@"synthesisGraph"]);
  if (value)
    [document setSynthesisGraph:value];
  value = ScoreProjectDecode ([platform objectForKey:@"compositionProgram"]);
  if (value)
    [document setCompositionProgram:value];
  return document;
}
@end
