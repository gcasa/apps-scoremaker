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
#import "ScoreModel.h"
#import "MusicPlatformModel.h"

/** Represents a note-on or note-off event on the playback timeline. */
@interface ScoreScheduledEvent : NSObject
{
  NSUInteger _tick;
  NSTimeInterval _time;
  ScoreNote *_note;
  BOOL _noteOff;
}
/** Absolute score tick. */
@property (nonatomic) NSUInteger tick;
/** Playback time in seconds from the start of the score. */
@property (nonatomic) NSTimeInterval time;
/** Note associated with this event. */
@property (nonatomic, retain) ScoreNote *note;
/** Whether the event releases rather than starts the note. */
@property (nonatomic) BOOL noteOff;
@end

/** Converts between score ticks and playback time using the tempo map. */
@interface ScoreScheduler : NSObject
{
  ScoreDocument *_document;
}

/** Initializes a scheduler using <var>document</var>'s notes and tempo events. */
- (id)initWithDocument:(ScoreDocument *)document;

/** Returns elapsed playback seconds at <var>tick</var>. */
- (NSTimeInterval)timeForTick:(NSUInteger)tick;

/** Returns the score tick reached at elapsed <var>time</var>. */
- (NSUInteger)tickForTime:(NSTimeInterval)time;

/** Returns ordered note-on and note-off events in the inclusive tick range. */
- (NSArray *)eventsFromTick:(NSUInteger)startTick throughTick:(NSUInteger)endTick;
@end

/** Applies enabled ScoreMIDIRoute rules to incoming MIDI messages. */
@interface ScoreMIDIRouter : NSObject
{
  ScoreDocument *_document;
}

/** Initializes a router backed by the routes in <var>document</var>. */
- (id)initWithDocument:(ScoreDocument *)document;

/**
 * Returns destination dictionaries after channel matching, transposition, and
 * velocity scaling have been applied to the source message.
 */
- (NSArray *)destinationsForSource:(NSString *)source
                           channel:(NSInteger)channel
                             pitch:(NSInteger)pitch
                          velocity:(NSUInteger)velocity;
@end

/** Contract implemented by playable instrument backends. */
@protocol ScoreInstrumentBackend <NSObject>

/** Returns the stable identifier stored in instrument definitions. */
- (NSString *)identifier;

/** Returns whether this backend can render without real-time playback. */
- (BOOL)supportsOfflineRendering;

/** Prepares <var>instrument</var>, returning details through <var>error</var>. */
- (void)prepareInstrument:(ScoreInstrumentDefinition *)instrument error:(NSError **)error;
@end

/** Process-wide registry mapping backend identifiers to backend objects. */
@interface ScoreInstrumentRegistry : NSObject
{
  NSMutableDictionary *_backends;
}

/** Returns the process-wide registry. */
+ (ScoreInstrumentRegistry *)sharedRegistry;

/** Registers or replaces a backend under its identifier. */
- (void)registerBackend:(id<ScoreInstrumentBackend>)backend;

/** Returns the backend registered for <var>identifier</var>, or <code>nil</code>. */
- (id<ScoreInstrumentBackend>)backendForIdentifier:(NSString *)identifier;
@end

/** Validates a synthesis graph and computes a topological processing order. */
@interface ScoreSynthesisCompiler : NSObject

/** Returns ordered graph nodes, or <code>nil</code> and an error for an invalid graph. */
+ (NSArray *)processingOrderForGraph:(ScoreSynthesisGraph *)graph error:(NSError **)error;
@end

/** Evaluates ScoreMaker composition-language programs into editable score data. */
@interface ScoreCompositionEvaluator : NSObject

/** Replaces generated content in <var>document</var> with evaluated program output. */
+ (BOOL)evaluateProgram:(ScoreCompositionProgram *)program
             inDocument:(ScoreDocument *)document
                  error:(NSError **)error;
@end
