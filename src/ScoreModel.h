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
@class ScorePageLayout;
@class ScoreSynthesisGraph;
@class ScoreCompositionProgram;
@class ScoreDocument;

/**
 * Represents a pitched note or rest at an absolute tick position. The object
 * also carries notation, performance, voice, and import-provenance metadata.
 */
@interface ScoreNote : NSObject <NSCopying>
{
  NSInteger _pitch;
  double _playbackFrequency;
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
  NSString *_lyric;
  NSString *_ornament;
  BOOL _grace;
  BOOL _cue;
  NSUInteger _tremoloStrokes;
  NSString *_hairpinStart;
  BOOL _hairpinEnd;
  BOOL _pedalStart;
  BOOL _pedalEnd;
  NSInteger _octaveShiftStart;
  BOOL _octaveShiftEnd;
  NSString *_directionText;
  NSInteger _staffAssignment;
  NSInteger _voice;
  NSInteger _measureIndex;
  NSUInteger _velocity;
  NSString *_provenance;
  NSMutableDictionary *_performanceParameters;
}

/** Returns the MIDI pitch number. */
- (NSInteger)pitch;

/** Sets the MIDI pitch number. */
- (void)setPitch:(NSInteger)pitch;

/** Returns the original playback frequency in hertz, or zero for equal temperament. */
- (double)playbackFrequency;

/** Preserves an exact source frequency while notation continues to use MIDI pitch. */
- (void)setPlaybackFrequency:(double)frequency;

/** Scorefile synthesis parameters retained for playback and round-trip export. */
- (NSMutableDictionary *)performanceParameters;

- (void)setPerformanceParameters:(NSMutableDictionary *)parameters;

/** Returns the zero-based MIDI channel. */
- (NSInteger)channel;

/** Sets the zero-based MIDI channel. */
- (void)setChannel:(NSInteger)channel;

/** Returns the legacy track number. */
- (NSInteger)track;

/** Sets the legacy track number. */
- (void)setTrack:(NSInteger)track;

/** Returns the absolute starting tick. */
- (NSUInteger)startTick;

/** Sets the absolute starting tick. */
- (void)setStartTick:(NSUInteger)startTick;

/** Returns the duration in score ticks. */
- (NSUInteger)durationTicks;

/** Sets the duration in score ticks. */
- (void)setDurationTicks:(NSUInteger)durationTicks;

/** Returns whether this event is a rest rather than a sounding note. */
- (BOOL)isRest;

/** Changes this event between a rest and a sounding note. */
- (void)setRest:(BOOL)rest;

/** Returns the explicit accidental: negative flat, zero none, positive sharp. */
- (NSInteger)accidental;

/** Sets the explicit accidental value. */
- (void)setAccidental:(NSInteger)accidental;

/** Returns whether a slur begins on this note. */
- (BOOL)slurStart;

/** Sets whether a slur begins on this note. */
- (void)setSlurStart:(BOOL)slurStart;

/** Returns whether a slur ends on this note. */
- (BOOL)slurEnd;

/** Sets whether a slur ends on this note. */
- (void)setSlurEnd:(BOOL)slurEnd;

/** Returns whether a tie begins on this note. */
- (BOOL)tieStart;

/** Sets whether a tie begins on this note. */
- (void)setTieStart:(BOOL)value;

/** Returns whether a tie ends on this note. */
- (BOOL)tieEnd;

/** Sets whether a tie ends on this note. */
- (void)setTieEnd:(BOOL)value;

/** Returns the performed-note count in the tuplet ratio, or zero. */
- (NSUInteger)tupletActual;

/** Sets the performed-note count in the tuplet ratio. */
- (void)setTupletActual:(NSUInteger)value;

/** Returns the normal-note count in the tuplet ratio, or zero. */
- (NSUInteger)tupletNormal;

/** Sets the normal-note count in the tuplet ratio. */
- (void)setTupletNormal:(NSUInteger)value;

/** Returns the dynamic marking, such as <code>p</code> or <code>ff</code>. */
- (NSString *)dynamic;

/** Sets the dynamic marking. */
- (void)setDynamic:(NSString *)value;

/** Returns the articulation name. */
- (NSString *)articulation;

/** Sets the articulation name. */
- (void)setArticulation:(NSString *)value;

/** Returns the lyric syllable aligned to this note. */
- (NSString *)lyric;

/** Sets the lyric syllable aligned to this note. */
- (void)setLyric:(NSString *)value;

/** Returns the ornament name, such as trill or turn. */
- (NSString *)ornament;

/** Sets the ornament name. */
- (void)setOrnament:(NSString *)value;

/** Returns whether this is an unmetered grace note. */
- (BOOL)isGrace;

/** Sets whether this is an unmetered grace note. */
- (void)setGrace:(BOOL)value;

/** Returns whether this note is printed at cue size. */
- (BOOL)isCue;

/** Sets whether this note is printed at cue size. */
- (void)setCue:(BOOL)value;

/** Returns the number of tremolo strokes. */
- (NSUInteger)tremoloStrokes;

/** Sets the number of tremolo strokes, clamped to zero through four. */
- (void)setTremoloStrokes:(NSUInteger)value;

/** Returns crescendo or diminuendo when a hairpin begins here. */
- (NSString *)hairpinStart;

- (void)setHairpinStart:(NSString *)value;

/** Returns whether a hairpin ends here. */
- (BOOL)hairpinEnd;

- (void)setHairpinEnd:(BOOL)value;

- (BOOL)pedalStart;

- (void)setPedalStart:(BOOL)value;

- (BOOL)pedalEnd;

- (void)setPedalEnd:(BOOL)value;

/** Returns octave displacement at the start: positive 8va, negative 8vb. */
- (NSInteger)octaveShiftStart;

- (void)setOctaveShiftStart:(NSInteger)value;

- (BOOL)octaveShiftEnd;

- (void)setOctaveShiftEnd:(BOOL)value;

/** Returns free score text anchored to this note. */
- (NSString *)directionText;

- (void)setDirectionText:(NSString *)value;

/** Returns 0 for automatic placement, 1 for upper staff, or 2 for lower staff. */
- (NSInteger)staffAssignment;

/** Sets automatic, upper-staff, or lower-staff placement. */
- (void)setStaffAssignment:(NSInteger)value;

/** Returns the one-based notation voice number. */
- (NSInteger)voice;

/** Sets the one-based notation voice number. */
- (void)setVoice:(NSInteger)voice;

/** Returns the zero-based containing-measure index. */
- (NSInteger)measureIndex;

/** Sets the zero-based containing-measure index. */
- (void)setMeasureIndex:(NSInteger)measureIndex;

/** Returns MIDI velocity in the range 0 through 127. */
- (NSUInteger)velocity;

/** Sets MIDI velocity. */
- (void)setVelocity:(NSUInteger)velocity;

/** Returns a textual description of the note's generated or imported origin. */
- (NSString *)provenance;

/** Sets the note's origin description. */
- (void)setProvenance:(NSString *)provenance;

/** Orders notes by score position and stable musical attributes. */
- (NSComparisonResult)compareScoreNote:(ScoreNote *)other;
@end

/** Describes one notated measure and its structural markings. */
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
  NSString *_rehearsalMark;
  NSString *_endingText;
  BOOL _systemBreak;
  BOOL _pageBreak;
}

/** Returns the displayed measure number. */
- (NSInteger)number;

/** Sets the displayed measure number. */
- (void)setNumber:(NSInteger)number;

/** Returns the measure's absolute starting tick. */
- (NSUInteger)startTick;

/** Sets the measure's absolute starting tick. */
- (void)setStartTick:(NSUInteger)startTick;

/** Returns the measure duration in score ticks. */
- (NSUInteger)durationTicks;

/** Sets the measure duration in score ticks. */
- (void)setDurationTicks:(NSUInteger)durationTicks;

/** Returns the number of beats in the local time signature. */
- (NSUInteger)timeSignatureNumerator;

/** Sets the number of beats in the local time signature. */
- (void)setTimeSignatureNumerator:(NSUInteger)value;

/** Returns the beat unit in the local time signature. */
- (NSUInteger)timeSignatureDenominator;

/** Sets the beat unit in the local time signature. */
- (void)setTimeSignatureDenominator:(NSUInteger)value;

/** Returns whether this is an implicit measure, such as a pickup. */
- (BOOL)isImplicit;

/** Sets whether this measure is implicit. */
- (void)setImplicit:(BOOL)implicit;

/** Returns key-signature fifths; negative values denote flats. */
- (NSInteger)keySignatureFifths;

/** Sets key-signature fifths. */
- (void)setKeySignatureFifths:(NSInteger)value;

/** Returns the key mode, normally <code>major</code> or <code>minor</code>. */
- (NSString *)keyMode;

/** Sets the key mode. */
- (void)setKeyMode:(NSString *)value;

/** Returns whether a forward repeat begins at this measure. */
- (BOOL)repeatStart;

/** Sets whether a forward repeat begins at this measure. */
- (void)setRepeatStart:(BOOL)value;

/** Returns whether a backward repeat ends at this measure. */
- (BOOL)repeatEnd;

/** Sets whether a backward repeat ends at this measure. */
- (void)setRepeatEnd:(BOOL)value;

/** Returns the rehearsal mark displayed at this measure. */
- (NSString *)rehearsalMark;

/** Sets the rehearsal mark displayed at this measure. */
- (void)setRehearsalMark:(NSString *)value;

/** Returns the volta/ending label, such as “1.” or “1, 2.”. */
- (NSString *)endingText;

/** Sets the volta/ending label. */
- (void)setEndingText:(NSString *)value;

/** Returns whether this measure begins a new system. */
- (BOOL)systemBreak;

/** Forces this measure to begin a new system. */
- (void)setSystemBreak:(BOOL)value;

/** Returns whether this measure begins a new page. */
- (BOOL)pageBreak;

/** Forces this measure to begin a new page (and therefore a new system). */
- (void)setPageBreak:(BOOL)value;
@end

/** Returns the key-signature alteration for diatonic step zero through six. */
FOUNDATION_EXPORT NSInteger ScoreKeySignatureAlterationForStep (NSInteger fifths,
                                                                NSInteger diatonicStep);
/** Returns flat, natural, sharp, or NSIntegerMax when no accidental is displayed. */
FOUNDATION_EXPORT NSInteger ScoreDisplayedAccidentalForNote (ScoreNote *note,
                                                             ScoreDocument *document);
/** Maps each note in <var>document</var> to its required displayed accidental. */
FOUNDATION_EXPORT NSDictionary *ScoreDisplayedAccidentalMapForDocument (ScoreDocument *document);

/**
 * Owns the complete editable score, including legacy note data and structured
 * parts, measures, tempo events, routes, and synthesis configuration.
 */
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
  ScorePageLayout *_pageLayout;
  NSMutableDictionary *_scorefileCompatibility;
}

/** Returns the score title. */
- (NSString *)title;

/** Sets the score title. */
- (void)setTitle:(NSString *)title;

/** Returns the PostScript name of the title font. */
- (NSString *)titleFontName;

/** Sets the PostScript name of the title font. */
- (void)setTitleFontName:(NSString *)fontName;

/** Returns the composer credit. */
- (NSString *)composer;

/** Sets the composer credit. */
- (void)setComposer:(NSString *)composer;

/** Returns the mutable array of ScoreNote instances. */
- (NSMutableArray *)notes;

/** Replaces the note array. */
- (void)setNotes:(NSMutableArray *)notes;

/** Returns the mutable array of ScoreMeasure instances. */
- (NSMutableArray *)measures;

/** Replaces the measure array. */
- (void)setMeasures:(NSMutableArray *)measures;

/** Rebuilds regular measures from duration and the document time signature. */
- (void)buildDefaultMeasures;

/** Returns the measure spanning <var>tick</var>, or <code>nil</code>. */
- (ScoreMeasure *)measureContainingTick:(NSUInteger)tick;

/** Returns the measure spanning <var>tick</var>, extending the score if necessary. */
- (ScoreMeasure *)ensureMeasureContainingTick:(NSUInteger)tick;

/** Returns the mutable mapping from legacy track numbers to part names. */
- (NSMutableDictionary *)partNames;

/** Replaces the legacy track-name mapping. */
- (void)setPartNames:(NSMutableDictionary *)partNames;

/** Returns the mutable mapping from legacy tracks to General MIDI programs. */
- (NSMutableDictionary *)trackPrograms;

/** Replaces the legacy track-program mapping. */
- (void)setTrackPrograms:(NSMutableDictionary *)trackPrograms;

/** Returns freeform score notes displayed by the inspector. */
- (NSString *)annotationText;

/** Sets freeform score notes. */
- (void)setAnnotationText:(NSString *)annotationText;

/** Returns timing resolution in ticks per quarter note. */
- (NSUInteger)ticksPerQuarter;

/** Sets timing resolution in ticks per quarter note. */
- (void)setTicksPerQuarter:(NSUInteger)ticksPerQuarter;

/** Returns the default tempo in microseconds per quarter note. */
- (NSUInteger)tempoMicrosecondsPerQuarter;

/** Sets the default tempo in microseconds per quarter note. */
- (void)setTempoMicrosecondsPerQuarter:(NSUInteger)tempoMicrosecondsPerQuarter;

/** Returns the document-level time-signature numerator. */
- (NSUInteger)timeSignatureNumerator;

/** Sets the document-level time-signature numerator. */
- (void)setTimeSignatureNumerator:(NSUInteger)timeSignatureNumerator;

/** Returns the document-level time-signature denominator. */
- (NSUInteger)timeSignatureDenominator;

/** Sets the document-level time-signature denominator. */
- (void)setTimeSignatureDenominator:(NSUInteger)timeSignatureDenominator;

/** Returns the total score duration in ticks. */
- (NSUInteger)totalTicks;

/** Sets the total score duration in ticks. */
- (void)setTotalTicks:(NSUInteger)totalTicks;

/** Lossless MusicKit compatibility data (source, declarations, envelopes and tunings). */
- (NSMutableDictionary *)scorefileCompatibility;

- (void)setScorefileCompatibility:(NSMutableDictionary *)compatibility;

/** Returns the display name for legacy <var>track</var>. */
- (NSString *)nameForTrack:(NSInteger)track;

/** Sets or removes the name for legacy <var>track</var>. */
- (void)setName:(NSString *)name forTrack:(NSInteger)track;

/** Returns the General MIDI program for legacy <var>track</var>. */
- (NSNumber *)programForTrack:(NSInteger)track;

/** Sets or removes the General MIDI program for legacy <var>track</var>. */
- (void)setProgram:(NSNumber *)program forTrack:(NSInteger)track;

/** Returns the mutable array of ScorePartDefinition instances. */
- (NSMutableArray *)parts;

/** Replaces the structured part array. */
- (void)setParts:(NSMutableArray *)parts;

/** Returns the mutable array of ScoreTempoEvent instances. */
- (NSMutableArray *)tempoEvents;

/** Replaces the tempo-event array. */
- (void)setTempoEvents:(NSMutableArray *)events;

/** Returns the mutable array of ScoreMIDIRoute instances. */
- (NSMutableArray *)midiRoutes;

/** Replaces the MIDI-route array. */
- (void)setMidiRoutes:(NSMutableArray *)routes;

/** Returns the document-level synthesis graph. */
- (ScoreSynthesisGraph *)synthesisGraph;

/** Replaces the document-level synthesis graph. */
- (void)setSynthesisGraph:(ScoreSynthesisGraph *)graph;

/** Returns the editable generative composition program. */
- (ScoreCompositionProgram *)compositionProgram;

/** Replaces the generative composition program. */
- (void)setCompositionProgram:(ScoreCompositionProgram *)program;

/** Returns publication settings used by screen, print, and PDF output. */
- (ScorePageLayout *)pageLayout;

/** Replaces the publication settings. */
- (void)setPageLayout:(ScorePageLayout *)layout;

/** Reconstructs structured parts and default routes from legacy tracks. */
- (void)rebuildStructuredPartsFromLegacyTracks;

/**
 * Copies persistent primary and fallback routing assignments from matching
 * legacy tracks in <var>document</var>.
 */
- (void)copyMIDIRoutingAssignmentsFromDocument:(ScoreDocument *)document;

/**
 * Splits every notation voice in <var>track</var> into its own part.  Notes in
 * each resulting part are normalized to voice 1.  Returns the number of
 * resulting parts, or zero when the track has fewer than two voices.
 */
- (NSUInteger)convertVoicesToPartsForTrack:(NSInteger)track;

/**
 * Combines all populated parts into the lowest-numbered part, assigning one
 * notation voice to each former part.  Returns the number of source parts, or
 * zero when fewer than two parts are present.
 */
- (NSUInteger)convertPartsToVoices;
@end
