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

#import "MusicPlatformModel.h"

static NSString *
ScoreNewIdentifier (void)
{
  return [[NSProcessInfo processInfo] globallyUniqueString];
}

@implementation ScoreInstrumentDefinition
@synthesize identifier = _identifier, name = _name, backendIdentifier = _backendIdentifier;
@synthesize program = _program, transposition = _transposition, lowestPitch = _lowestPitch;
@synthesize highestPitch = _highestPitch, parameters = _parameters;
- (id)init
{
  if ((self = [super init]))
    {
      _identifier = [ScoreNewIdentifier () copy];
      _backendIdentifier = [@"general-midi" copy];
      _lowestPitch = 0;
      _highestPitch = 127;
      _parameters = [[NSMutableDictionary alloc] init];
    }
  return self;
}
- (id)copyWithZone:(NSZone *)zone
{
  ScoreInstrumentDefinition *copy = [[ScoreInstrumentDefinition allocWithZone:zone] init];
  copy.identifier = _identifier;
  copy.name = _name;
  copy.backendIdentifier = _backendIdentifier;
  copy.program = _program;
  copy.transposition = _transposition;
  copy.lowestPitch = _lowestPitch;
  copy.highestPitch = _highestPitch;
  copy.parameters = [[_parameters mutableCopy] autorelease];
  return copy;
}
- (void)dealloc
{
  [_identifier release];
  [_name release];
  [_backendIdentifier release];
  [_parameters release];
  [super dealloc];
}
@end

@implementation ScoreVoiceDefinition
@synthesize identifier = _identifier, number = _number;
@synthesize preferredStemDirection = _preferredStemDirection;
- (id)init
{
  if ((self = [super init]))
    {
      _identifier = [ScoreNewIdentifier () copy];
      _number = 1;
    }
  return self;
}
- (id)copyWithZone:(NSZone *)zone
{
  ScoreVoiceDefinition *copy = [[ScoreVoiceDefinition allocWithZone:zone] init];
  copy.identifier = _identifier;
  copy.number = _number;
  copy.preferredStemDirection = _preferredStemDirection;
  return copy;
}
- (void)dealloc
{
  [_identifier release];
  [super dealloc];
}
@end

@implementation ScoreStaffDefinition
@synthesize identifier = _identifier, clef = _clef, voices = _voices;
- (id)init
{
  if ((self = [super init]))
    {
      _identifier = [ScoreNewIdentifier () copy];
      _voices = [[NSMutableArray alloc] init];
    }
  return self;
}
- (id)copyWithZone:(NSZone *)zone
{
  ScoreStaffDefinition *copy = [[ScoreStaffDefinition allocWithZone:zone] init];
  copy.identifier = _identifier;
  copy.clef = _clef;
  copy.voices = [[[NSMutableArray alloc] initWithArray:_voices copyItems:YES] autorelease];
  return copy;
}
- (void)dealloc
{
  [_identifier release];
  [_voices release];
  [super dealloc];
}
@end

@implementation ScorePartDefinition
@synthesize identifier = _identifier, name = _name, abbreviatedName = _abbreviatedName;
@synthesize legacyTrack = _legacyTrack, visible = _visible, instrument = _instrument,
            staves = _staves;
@synthesize midiOutputUniqueID = _midiOutputUniqueID, midiOutputName = _midiOutputName;
@synthesize synthesisGraph = _synthesisGraph;
- (id)init
{
  if ((self = [super init]))
    {
      _identifier = [ScoreNewIdentifier () copy];
      _visible = YES;
      _staves = [[NSMutableArray alloc] init];
      _synthesisGraph = [[ScoreSynthesisGraph alloc] init];
    }
  return self;
}
- (id)copyWithZone:(NSZone *)zone
{
  ScorePartDefinition *copy = [[ScorePartDefinition allocWithZone:zone] init];
  copy.identifier = _identifier;
  copy.name = _name;
  copy.abbreviatedName = _abbreviatedName;
  copy.legacyTrack = _legacyTrack;
  copy.visible = _visible;
  copy.midiOutputUniqueID = _midiOutputUniqueID;
  copy.midiOutputName = _midiOutputName;
  copy.instrument = [[_instrument copy] autorelease];
  copy.staves = [[[NSMutableArray alloc] initWithArray:_staves copyItems:YES] autorelease];
  copy.synthesisGraph = [[_synthesisGraph copy] autorelease];
  return copy;
}
- (void)dealloc
{
  [_identifier release];
  [_name release];
  [_abbreviatedName release];
  [_midiOutputName release];
  [_instrument release];
  [_staves release];
  [_synthesisGraph release];
  [super dealloc];
}
@end

@implementation ScoreTempoEvent
@synthesize tick = _tick, microsecondsPerQuarter = _microsecondsPerQuarter;
- (id)copyWithZone:(NSZone *)zone
{
  ScoreTempoEvent *copy = [[ScoreTempoEvent allocWithZone:zone] init];
  copy.tick = _tick;
  copy.microsecondsPerQuarter = _microsecondsPerQuarter;
  return copy;
}
@end

@implementation ScoreMIDIRoute
@synthesize identifier = _identifier, sourceIdentifier = _sourceIdentifier;
@synthesize sourceChannel = _sourceChannel, destinationPartIdentifier = _destinationPartIdentifier;
@synthesize destinationChannel = _destinationChannel, transposition = _transposition;
@synthesize velocityScale = _velocityScale, enabled = _enabled;
- (id)init
{
  if ((self = [super init]))
    {
      _identifier = [ScoreNewIdentifier () copy];
      _sourceChannel = -1;
      _destinationChannel = -1;
      _velocityScale = 1.0;
      _enabled = YES;
    }
  return self;
}
- (id)copyWithZone:(NSZone *)zone
{
  ScoreMIDIRoute *copy = [[ScoreMIDIRoute allocWithZone:zone] init];
  copy.identifier = _identifier;
  copy.sourceIdentifier = _sourceIdentifier;
  copy.sourceChannel = _sourceChannel;
  copy.destinationPartIdentifier = _destinationPartIdentifier;
  copy.destinationChannel = _destinationChannel;
  copy.transposition = _transposition;
  copy.velocityScale = _velocityScale;
  copy.enabled = _enabled;
  return copy;
}
- (void)dealloc
{
  [_identifier release];
  [_sourceIdentifier release];
  [_destinationPartIdentifier release];
  [super dealloc];
}
@end

@implementation ScoreSynthesisNode
@synthesize identifier = _identifier, typeIdentifier = _typeIdentifier, parameters = _parameters;
- (id)init
{
  if ((self = [super init]))
    {
      _identifier = [ScoreNewIdentifier () copy];
      _parameters = [[NSMutableDictionary alloc] init];
    }
  return self;
}
- (id)copyWithZone:(NSZone *)zone
{
  ScoreSynthesisNode *copy = [[ScoreSynthesisNode allocWithZone:zone] init];
  copy.identifier = _identifier;
  copy.typeIdentifier = _typeIdentifier;
  copy.parameters = [[_parameters mutableCopy] autorelease];
  return copy;
}
- (void)dealloc
{
  [_identifier release];
  [_typeIdentifier release];
  [_parameters release];
  [super dealloc];
}
@end

@implementation ScoreSynthesisConnection
@synthesize sourceNodeIdentifier = _sourceNodeIdentifier, sourcePort = _sourcePort;
@synthesize destinationNodeIdentifier = _destinationNodeIdentifier,
            destinationPort = _destinationPort;
- (id)copyWithZone:(NSZone *)zone
{
  ScoreSynthesisConnection *copy = [[ScoreSynthesisConnection allocWithZone:zone] init];
  copy.sourceNodeIdentifier = _sourceNodeIdentifier;
  copy.sourcePort = _sourcePort;
  copy.destinationNodeIdentifier = _destinationNodeIdentifier;
  copy.destinationPort = _destinationPort;
  return copy;
}
- (void)dealloc
{
  [_sourceNodeIdentifier release];
  [_sourcePort release];
  [_destinationNodeIdentifier release];
  [_destinationPort release];
  [super dealloc];
}
@end

@implementation ScoreSynthesisGraph
@synthesize nodes = _nodes, connections = _connections;
- (id)init
{
  if ((self = [super init]))
    {
      _nodes = [[NSMutableArray alloc] init];
      _connections = [[NSMutableArray alloc] init];
    }
  return self;
}
- (BOOL)validateWithError:(NSError **)error
{
  NSMutableSet *identifiers = [NSMutableSet set];
  for (ScoreSynthesisNode *node in _nodes)
    {
      if ([[node identifier] length] == 0 || [identifiers containsObject:[node identifier]])
        {
          if (error)
            *error = [NSError
              errorWithDomain:@"ScoreMakerSynthesisGraph"
                         code:1
                     userInfo:[NSDictionary
                                dictionaryWithObject:@"Synthesis node identifiers must be unique."
                                              forKey:NSLocalizedDescriptionKey]];
          return NO;
        }
      [identifiers addObject:[node identifier]];
    }
  for (ScoreSynthesisConnection *connection in _connections)
    if (![identifiers containsObject:[connection sourceNodeIdentifier]]
        || ![identifiers containsObject:[connection destinationNodeIdentifier]])
      {
        if (error)
          *error = [NSError
            errorWithDomain:@"ScoreMakerSynthesisGraph"
                       code:2
                   userInfo:[NSDictionary dictionaryWithObject:
                                            @"A synthesis connection references a missing node."
                                                        forKey:NSLocalizedDescriptionKey]];
        return NO;
      }
  return YES;
}
- (id)copyWithZone:(NSZone *)zone
{
  ScoreSynthesisGraph *copy = [[ScoreSynthesisGraph allocWithZone:zone] init];
  copy.nodes = [[[NSMutableArray alloc] initWithArray:_nodes copyItems:YES] autorelease];
  copy.connections = [[[NSMutableArray alloc] initWithArray:_connections
                                                  copyItems:YES] autorelease];
  return copy;
}
- (void)dealloc
{
  [_nodes release];
  [_connections release];
  [super dealloc];
}
@end

@implementation ScoreCompositionProgram
@synthesize source = _source, diagnostics = _diagnostics;
- (id)init
{
  if ((self = [super init]))
    {
      _source = [@"" copy];
      _diagnostics = [[NSMutableArray alloc] init];
    }
  return self;
}
- (id)copyWithZone:(NSZone *)zone
{
  ScoreCompositionProgram *copy = [[ScoreCompositionProgram allocWithZone:zone] init];
  copy.source = _source;
  copy.diagnostics = [[_diagnostics mutableCopy] autorelease];
  return copy;
}
- (void)dealloc
{
  [_source release];
  [_diagnostics release];
  [super dealloc];
}
@end
