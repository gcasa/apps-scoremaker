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

#import <Foundation/Foundation.h>

@class ScoreSynthesisGraph;

typedef NS_ENUM (NSInteger, ScoreStaffClef) {
  ScoreStaffClefTreble,
  ScoreStaffClefBass,
  ScoreStaffClefAlto,
  ScoreStaffClefTenor,
  ScoreStaffClefPercussion
};

@interface ScoreInstrumentDefinition : NSObject <NSCopying>
{
  NSString *_identifier;
  NSString *_name;
  NSString *_backendIdentifier;
  NSInteger _program;
  NSInteger _transposition;
  NSInteger _lowestPitch;
  NSInteger _highestPitch;
  NSMutableDictionary *_parameters;
}
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *backendIdentifier;
@property (nonatomic) NSInteger program;
@property (nonatomic) NSInteger transposition;
@property (nonatomic) NSInteger lowestPitch;
@property (nonatomic) NSInteger highestPitch;
@property (nonatomic, retain) NSMutableDictionary *parameters;
@end

@interface ScoreVoiceDefinition : NSObject <NSCopying>
{
  NSString *_identifier;
  NSInteger _number;
  NSInteger _preferredStemDirection;
}
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic) NSInteger number;
@property (nonatomic) NSInteger preferredStemDirection;
@end

@interface ScoreStaffDefinition : NSObject <NSCopying>
{
  NSString *_identifier;
  ScoreStaffClef _clef;
  NSMutableArray *_voices;
}
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic) ScoreStaffClef clef;
@property (nonatomic, retain) NSMutableArray *voices;
@end

@interface ScorePartDefinition : NSObject <NSCopying>
{
  NSString *_identifier;
  NSString *_name;
  NSString *_abbreviatedName;
  NSInteger _legacyTrack;
  BOOL _visible;
  NSInteger _midiOutputUniqueID;
  NSString *_midiOutputName;
  NSString *_midiFallbackMode;
  NSInteger _midiFallbackUniqueID;
  NSString *_midiFallbackName;
  ScoreInstrumentDefinition *_instrument;
  NSMutableArray *_staves;
  ScoreSynthesisGraph *_synthesisGraph;
}
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *abbreviatedName;
@property (nonatomic) NSInteger legacyTrack;
@property (nonatomic) BOOL visible;
/* 0 selects the built-in synthesizer. Positive or negative CoreMIDI unique IDs select a
   physical destination on macOS; other platforms preserve the assignment without using it. */
@property (nonatomic) NSInteger midiOutputUniqueID;
@property (nonatomic, copy) NSString *midiOutputName;
/* Fallback modes are "builtin", "silent", and "device". */
@property (nonatomic, copy) NSString *midiFallbackMode;
@property (nonatomic) NSInteger midiFallbackUniqueID;
@property (nonatomic, copy) NSString *midiFallbackName;
@property (nonatomic, retain) ScoreInstrumentDefinition *instrument;
@property (nonatomic, retain) NSMutableArray *staves;
@property (nonatomic, retain) ScoreSynthesisGraph *synthesisGraph;
@end

@interface ScoreTempoEvent : NSObject <NSCopying>
{
  NSUInteger _tick;
  NSUInteger _microsecondsPerQuarter;
}
@property (nonatomic) NSUInteger tick;
@property (nonatomic) NSUInteger microsecondsPerQuarter;
@end

@interface ScoreMIDIRoute : NSObject <NSCopying>
{
  NSString *_identifier;
  NSString *_sourceIdentifier;
  NSInteger _sourceChannel;
  NSString *_destinationPartIdentifier;
  NSInteger _destinationChannel;
  NSInteger _transposition;
  CGFloat _velocityScale;
  BOOL _enabled;
}
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *sourceIdentifier;
@property (nonatomic) NSInteger sourceChannel;
@property (nonatomic, copy) NSString *destinationPartIdentifier;
@property (nonatomic) NSInteger destinationChannel;
@property (nonatomic) NSInteger transposition;
@property (nonatomic) CGFloat velocityScale;
@property (nonatomic) BOOL enabled;
@end

@interface ScoreSynthesisNode : NSObject <NSCopying>
{
  NSString *_identifier;
  NSString *_typeIdentifier;
  NSMutableDictionary *_parameters;
}
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *typeIdentifier;
@property (nonatomic, retain) NSMutableDictionary *parameters;
@end

@interface ScoreSynthesisConnection : NSObject <NSCopying>
{
  NSString *_sourceNodeIdentifier;
  NSString *_sourcePort;
  NSString *_destinationNodeIdentifier;
  NSString *_destinationPort;
}
@property (nonatomic, copy) NSString *sourceNodeIdentifier;
@property (nonatomic, copy) NSString *sourcePort;
@property (nonatomic, copy) NSString *destinationNodeIdentifier;
@property (nonatomic, copy) NSString *destinationPort;
@end

@interface ScoreSynthesisGraph : NSObject <NSCopying>
{
  NSMutableArray *_nodes;
  NSMutableArray *_connections;
}
@property (nonatomic, retain) NSMutableArray *nodes;
@property (nonatomic, retain) NSMutableArray *connections;
- (BOOL)validateWithError:(NSError **)error;
@end

@interface ScoreCompositionProgram : NSObject <NSCopying>
{
  NSString *_source;
  NSMutableArray *_diagnostics;
}
@property (nonatomic, copy) NSString *source;
@property (nonatomic, retain) NSMutableArray *diagnostics;
@end
