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

/** Identifies the clef used to interpret and render a staff. */
typedef NS_ENUM (NSInteger, ScoreStaffClef) {
  /** Treble or G clef. */
  ScoreStaffClefTreble,
  /** Bass or F clef. */
  ScoreStaffClefBass,
  /** Alto C clef. */
  ScoreStaffClefAlto,
  /** Tenor C clef. */
  ScoreStaffClefTenor,
  /** Unpitched percussion clef. */
  ScoreStaffClefPercussion
};

/** Describes the playable instrument assigned to a score part. */
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
/** Stable identifier used by routes and serialized projects. */
@property (nonatomic, copy) NSString *identifier;
/** User-visible instrument name. */
@property (nonatomic, copy) NSString *name;
/** Identifier of the synthesis or plug-in backend. */
@property (nonatomic, copy) NSString *backendIdentifier;
/** Zero-based General MIDI program number. */
@property (nonatomic) NSInteger program;
/** Playback transposition in semitones. */
@property (nonatomic) NSInteger transposition;
/** Lowest recommended MIDI pitch. */
@property (nonatomic) NSInteger lowestPitch;
/** Highest recommended MIDI pitch. */
@property (nonatomic) NSInteger highestPitch;
/** Backend-specific, property-list-compatible configuration. */
@property (nonatomic, retain) NSMutableDictionary *parameters;
@end

/** Describes one independently stemmed notation voice on a staff. */
@interface ScoreVoiceDefinition : NSObject <NSCopying>
{
  NSString *_identifier;
  NSInteger _number;
  NSInteger _preferredStemDirection;
}
/** Stable voice identifier. */
@property (nonatomic, copy) NSString *identifier;
/** One-based notation voice number. */
@property (nonatomic) NSInteger number;
/** Preferred stem direction: negative down, positive up, or zero automatic. */
@property (nonatomic) NSInteger preferredStemDirection;
@end

/** Defines a staff and the notation voices displayed on it. */
@interface ScoreStaffDefinition : NSObject <NSCopying>
{
  NSString *_identifier;
  ScoreStaffClef _clef;
  NSMutableArray *_voices;
}
/** Stable staff identifier. */
@property (nonatomic, copy) NSString *identifier;
/** Clef used by this staff. */
@property (nonatomic) ScoreStaffClef clef;
/** Mutable array of ScoreVoiceDefinition instances. */
@property (nonatomic, retain) NSMutableArray *voices;
@end

/**
 * Defines a musical part, including notation, instrument, and persistent MIDI
 * routing state.
 */
@interface ScorePartDefinition : NSObject <NSCopying>
{
  NSString *_identifier;
  NSString *_name;
  NSString *_abbreviatedName;
  NSInteger _legacyTrack;
  BOOL _visible;
  BOOL _muted;
  BOOL _soloed;
  CGFloat _gain;
  CGFloat _pan;
  NSString *_groupName;
  NSInteger _midiOutputUniqueID;
  NSString *_midiOutputName;
  NSString *_midiFallbackMode;
  NSInteger _midiFallbackUniqueID;
  NSString *_midiFallbackName;
  ScoreInstrumentDefinition *_instrument;
  NSMutableArray *_staves;
  ScoreSynthesisGraph *_synthesisGraph;
}
/** Stable identifier referenced by MIDI routes. */
@property (nonatomic, copy) NSString *identifier;
/** Full display name. */
@property (nonatomic, copy) NSString *name;
/** Abbreviated name used where horizontal space is limited. */
@property (nonatomic, copy) NSString *abbreviatedName;
/** Track number used by legacy score and MIDI representations. */
@property (nonatomic) NSInteger legacyTrack;
/** Whether the part participates in normal score display. */
@property (nonatomic) BOOL visible;
/** Whether playback of this part is suppressed. */
@property (nonatomic) BOOL muted;
/** Whether this part participates in the mixer solo set. */
@property (nonatomic) BOOL soloed;
/** Linear playback gain in the range 0 through 2. */
@property (nonatomic) CGFloat gain;
/** Stereo position in the range -1 (left) through 1 (right). */
@property (nonatomic) CGFloat pan;
/** Optional user-visible ensemble or section grouping. */
@property (nonatomic, copy) NSString *groupName;
/**
 * Persistent output assignment. Zero selects the built-in synthesizer;
 * nonzero values are CoreMIDI endpoint unique identifiers on macOS.
 */
@property (nonatomic) NSInteger midiOutputUniqueID;
/** Last-known output name, used to reconnect when an endpoint identifier changes. */
@property (nonatomic, copy) NSString *midiOutputName;
/** Fallback mode: <code>builtin</code>, <code>silent</code>, or <code>device</code>. */
@property (nonatomic, copy) NSString *midiFallbackMode;
/** Unique identifier of the fallback endpoint when the mode is <code>device</code>. */
@property (nonatomic) NSInteger midiFallbackUniqueID;
/** Last-known name of the fallback endpoint. */
@property (nonatomic, copy) NSString *midiFallbackName;
/** Instrument assigned to the part. */
@property (nonatomic, retain) ScoreInstrumentDefinition *instrument;
/** Mutable array of ScoreStaffDefinition instances. */
@property (nonatomic, retain) NSMutableArray *staves;
/** Per-part synthesis and effects graph. */
@property (nonatomic, retain) ScoreSynthesisGraph *synthesisGraph;
@end

/** Persistent publication settings shared by screen, print, and PDF output. */
@interface ScorePageLayout : NSObject <NSCopying>
{
  CGFloat _paperWidth;
  CGFloat _paperHeight;
  CGFloat _marginTop;
  CGFloat _marginRight;
  CGFloat _marginBottom;
  CGFloat _marginLeft;
  CGFloat _staffScale;
  CGFloat _systemSpacing;
  BOOL _showPageNumbers;
  BOOL _showHeaders;
  NSString *_headerText;
  NSString *_footerText;
}
@property (nonatomic) CGFloat paperWidth;
@property (nonatomic) CGFloat paperHeight;
@property (nonatomic) CGFloat marginTop;
@property (nonatomic) CGFloat marginRight;
@property (nonatomic) CGFloat marginBottom;
@property (nonatomic) CGFloat marginLeft;
@property (nonatomic) CGFloat staffScale;
@property (nonatomic) CGFloat systemSpacing;
@property (nonatomic) BOOL showPageNumbers;
@property (nonatomic) BOOL showHeaders;
@property (nonatomic, copy) NSString *headerText;
@property (nonatomic, copy) NSString *footerText;
@end

/** Represents a tempo change at an absolute score tick. */
@interface ScoreTempoEvent : NSObject <NSCopying>
{
  NSUInteger _tick;
  NSUInteger _microsecondsPerQuarter;
}
/** Absolute tick at which the tempo takes effect. */
@property (nonatomic) NSUInteger tick;
/** Tempo expressed as microseconds per quarter note. */
@property (nonatomic) NSUInteger microsecondsPerQuarter;
@end

/** Maps an input source and channel to a destination part and channel. */
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
/** Stable route identifier. */
@property (nonatomic, copy) NSString *identifier;
/** Identifier of the input source matched by this route. */
@property (nonatomic, copy) NSString *sourceIdentifier;
/** Zero-based input MIDI channel, or a negative value for any channel. */
@property (nonatomic) NSInteger sourceChannel;
/** Identifier of the destination ScorePartDefinition. */
@property (nonatomic, copy) NSString *destinationPartIdentifier;
/** Zero-based output MIDI channel. */
@property (nonatomic) NSInteger destinationChannel;
/** Pitch transposition in semitones. */
@property (nonatomic) NSInteger transposition;
/** Multiplicative velocity adjustment. */
@property (nonatomic) CGFloat velocityScale;
/** Whether the route participates in routing. */
@property (nonatomic) BOOL enabled;
@end

/** Represents a processor or generator in a synthesis graph. */
@interface ScoreSynthesisNode : NSObject <NSCopying>
{
  NSString *_identifier;
  NSString *_typeIdentifier;
  NSMutableDictionary *_parameters;
}
/** Stable node identifier used by graph connections. */
@property (nonatomic, copy) NSString *identifier;
/** Processor type, such as oscillator, gain, delay, or reverb. */
@property (nonatomic, copy) NSString *typeIdentifier;
/** Mutable type-specific parameter dictionary. */
@property (nonatomic, retain) NSMutableDictionary *parameters;
@end

/** Describes a directed connection between two synthesis-node ports. */
@interface ScoreSynthesisConnection : NSObject <NSCopying>
{
  NSString *_sourceNodeIdentifier;
  NSString *_sourcePort;
  NSString *_destinationNodeIdentifier;
  NSString *_destinationPort;
}
/** Identifier of the node producing the signal. */
@property (nonatomic, copy) NSString *sourceNodeIdentifier;
/** Name of the producing node's output port. */
@property (nonatomic, copy) NSString *sourcePort;
/** Identifier of the node receiving the signal. */
@property (nonatomic, copy) NSString *destinationNodeIdentifier;
/** Name of the receiving node's input port. */
@property (nonatomic, copy) NSString *destinationPort;
@end

/** Owns synthesis nodes and the directed connections between them. */
@interface ScoreSynthesisGraph : NSObject <NSCopying>
{
  NSMutableArray *_nodes;
  NSMutableArray *_connections;
}
/** Mutable array of ScoreSynthesisNode instances. */
@property (nonatomic, retain) NSMutableArray *nodes;
/** Mutable array of ScoreSynthesisConnection instances. */
@property (nonatomic, retain) NSMutableArray *connections;
/**
 * Validates identifiers, endpoints, and graph acyclicity. Returns
 * <code>YES</code> when the graph can be compiled.
 */
- (BOOL)validateWithError:(NSError **)error;
@end

/** Stores editable composition-program source and its latest diagnostics. */
@interface ScoreCompositionProgram : NSObject <NSCopying>
{
  NSString *_source;
  NSMutableArray *_diagnostics;
}
/** Composition language source text. */
@property (nonatomic, copy) NSString *source;
/** Mutable array of evaluator diagnostic dictionaries. */
@property (nonatomic, retain) NSMutableArray *diagnostics;
@end
