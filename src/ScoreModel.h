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

@class ScorePartDefinition;
@class ScoreTempoEvent;
@class ScoreMIDIRoute;
@class ScoreSynthesisGraph;
@class ScoreCompositionProgram;
@class ScoreDocument;

@interface ScoreNote : NSObject <NSCopying>
{
  NSInteger _pitch;
  NSInteger _channel;
  NSInteger _track;
  NSUInteger _startTick;
  NSUInteger _durationTicks;
  BOOL _rest;
  NSInteger _accidental;
  BOOL _slurStart;
  BOOL _slurEnd;
  BOOL _tieStart;
  BOOL _tieEnd;
  NSUInteger _tupletActual;
  NSUInteger _tupletNormal;
  NSString *_dynamic;
  NSString *_articulation;
  NSInteger _voice;
  NSInteger _measureIndex;
  NSUInteger _velocity;
  NSString *_provenance;
}
- (NSInteger)pitch;
- (void)setPitch:(NSInteger)pitch;
- (NSInteger)channel;
- (void)setChannel:(NSInteger)channel;
- (NSInteger)track;
- (void)setTrack:(NSInteger)track;
- (NSUInteger)startTick;
- (void)setStartTick:(NSUInteger)startTick;
- (NSUInteger)durationTicks;
- (void)setDurationTicks:(NSUInteger)durationTicks;
- (BOOL)isRest;
- (void)setRest:(BOOL)rest;
- (NSInteger)accidental;
- (void)setAccidental:(NSInteger)accidental;
- (BOOL)slurStart;
- (void)setSlurStart:(BOOL)slurStart;
- (BOOL)slurEnd;
- (void)setSlurEnd:(BOOL)slurEnd;
- (BOOL)tieStart;
- (void)setTieStart:(BOOL)value;
- (BOOL)tieEnd;
- (void)setTieEnd:(BOOL)value;
- (NSUInteger)tupletActual;
- (void)setTupletActual:(NSUInteger)value;
- (NSUInteger)tupletNormal;
- (void)setTupletNormal:(NSUInteger)value;
- (NSString *)dynamic;
- (void)setDynamic:(NSString *)value;
- (NSString *)articulation;
- (void)setArticulation:(NSString *)value;
- (NSInteger)voice;
- (void)setVoice:(NSInteger)voice;
- (NSInteger)measureIndex;
- (void)setMeasureIndex:(NSInteger)measureIndex;
- (NSUInteger)velocity;
- (void)setVelocity:(NSUInteger)velocity;
- (NSString *)provenance;
- (void)setProvenance:(NSString *)provenance;
- (NSComparisonResult)compareScoreNote:(ScoreNote *)other;
@end

@interface ScoreMeasure : NSObject <NSCopying>
{
  NSInteger _number;
  NSUInteger _startTick;
  NSUInteger _durationTicks;
  NSUInteger _timeSignatureNumerator;
  NSUInteger _timeSignatureDenominator;
  BOOL _implicit;
  NSInteger _keySignatureFifths;
  NSString *_keyMode;
  BOOL _repeatStart;
  BOOL _repeatEnd;
}
- (NSInteger)number;
- (void)setNumber:(NSInteger)number;
- (NSUInteger)startTick;
- (void)setStartTick:(NSUInteger)startTick;
- (NSUInteger)durationTicks;
- (void)setDurationTicks:(NSUInteger)durationTicks;
- (NSUInteger)timeSignatureNumerator;
- (void)setTimeSignatureNumerator:(NSUInteger)value;
- (NSUInteger)timeSignatureDenominator;
- (void)setTimeSignatureDenominator:(NSUInteger)value;
- (BOOL)isImplicit;
- (void)setImplicit:(BOOL)implicit;
- (NSInteger)keySignatureFifths;
- (void)setKeySignatureFifths:(NSInteger)value;
- (NSString *)keyMode;
- (void)setKeyMode:(NSString *)value;
- (BOOL)repeatStart;
- (void)setRepeatStart:(BOOL)value;
- (BOOL)repeatEnd;
- (void)setRepeatEnd:(BOOL)value;
@end

FOUNDATION_EXPORT NSInteger ScoreKeySignatureAlterationForStep (NSInteger fifths,
                                                                 NSInteger diatonicStep);
/* Returns -1 (flat), 0 (natural), 1 (sharp), or NSIntegerMax when no glyph is needed. */
FOUNDATION_EXPORT NSInteger ScoreDisplayedAccidentalForNote (ScoreNote *note,
                                                              ScoreDocument *document);
FOUNDATION_EXPORT NSDictionary *ScoreDisplayedAccidentalMapForDocument (ScoreDocument *document);

@interface ScoreDocument : NSObject <NSCopying>
{
  NSString *_title;
  NSString *_titleFontName;
  NSString *_composer;
  NSMutableArray *_notes;
  NSMutableArray *_measures;
  NSMutableDictionary *_partNames;
  NSMutableDictionary *_trackPrograms;
  NSString *_annotationText;
  NSUInteger _ticksPerQuarter;
  NSUInteger _tempoMicrosecondsPerQuarter;
  NSUInteger _timeSignatureNumerator;
  NSUInteger _timeSignatureDenominator;
  NSUInteger _totalTicks;
  NSMutableArray *_parts;
  NSMutableArray *_tempoEvents;
  NSMutableArray *_midiRoutes;
  ScoreSynthesisGraph *_synthesisGraph;
  ScoreCompositionProgram *_compositionProgram;
}
- (NSString *)title;
- (void)setTitle:(NSString *)title;
- (NSString *)titleFontName;
- (void)setTitleFontName:(NSString *)fontName;
- (NSString *)composer;
- (void)setComposer:(NSString *)composer;
- (NSMutableArray *)notes;
- (void)setNotes:(NSMutableArray *)notes;
- (NSMutableArray *)measures;
- (void)setMeasures:(NSMutableArray *)measures;
- (void)buildDefaultMeasures;
- (ScoreMeasure *)measureContainingTick:(NSUInteger)tick;
- (ScoreMeasure *)ensureMeasureContainingTick:(NSUInteger)tick;
- (NSMutableDictionary *)partNames;
- (void)setPartNames:(NSMutableDictionary *)partNames;
- (NSMutableDictionary *)trackPrograms;
- (void)setTrackPrograms:(NSMutableDictionary *)trackPrograms;
- (NSString *)annotationText;
- (void)setAnnotationText:(NSString *)annotationText;
- (NSUInteger)ticksPerQuarter;
- (void)setTicksPerQuarter:(NSUInteger)ticksPerQuarter;
- (NSUInteger)tempoMicrosecondsPerQuarter;
- (void)setTempoMicrosecondsPerQuarter:(NSUInteger)tempoMicrosecondsPerQuarter;
- (NSUInteger)timeSignatureNumerator;
- (void)setTimeSignatureNumerator:(NSUInteger)timeSignatureNumerator;
- (NSUInteger)timeSignatureDenominator;
- (void)setTimeSignatureDenominator:(NSUInteger)timeSignatureDenominator;
- (NSUInteger)totalTicks;
- (void)setTotalTicks:(NSUInteger)totalTicks;
- (NSString *)nameForTrack:(NSInteger)track;
- (void)setName:(NSString *)name forTrack:(NSInteger)track;
- (NSNumber *)programForTrack:(NSInteger)track;
- (void)setProgram:(NSNumber *)program forTrack:(NSInteger)track;
- (NSMutableArray *)parts;
- (void)setParts:(NSMutableArray *)parts;
- (NSMutableArray *)tempoEvents;
- (void)setTempoEvents:(NSMutableArray *)events;
- (NSMutableArray *)midiRoutes;
- (void)setMidiRoutes:(NSMutableArray *)routes;
- (ScoreSynthesisGraph *)synthesisGraph;
- (void)setSynthesisGraph:(ScoreSynthesisGraph *)graph;
- (ScoreCompositionProgram *)compositionProgram;
- (void)setCompositionProgram:(ScoreCompositionProgram *)program;
- (void)rebuildStructuredPartsFromLegacyTracks;
@end
