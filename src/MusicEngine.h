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

@interface ScoreScheduledEvent : NSObject
{
  NSUInteger _tick;
  NSTimeInterval _time;
  ScoreNote *_note;
  BOOL _noteOff;
}
@property (nonatomic) NSUInteger tick;
@property (nonatomic) NSTimeInterval time;
@property (nonatomic, retain) ScoreNote *note;
@property (nonatomic) BOOL noteOff;
@end

@interface ScoreScheduler : NSObject
{
  ScoreDocument *_document;
}
- (id)initWithDocument:(ScoreDocument *)document;
- (NSTimeInterval)timeForTick:(NSUInteger)tick;
- (NSUInteger)tickForTime:(NSTimeInterval)time;
- (NSArray *)eventsFromTick:(NSUInteger)startTick throughTick:(NSUInteger)endTick;
@end

@interface ScoreMIDIRouter : NSObject
{
  ScoreDocument *_document;
}
- (id)initWithDocument:(ScoreDocument *)document;
- (NSArray *)destinationsForSource:(NSString *)source
                           channel:(NSInteger)channel
                             pitch:(NSInteger)pitch
                          velocity:(NSUInteger)velocity;
@end

@protocol ScoreInstrumentBackend <NSObject>
- (NSString *)identifier;
- (BOOL)supportsOfflineRendering;
- (void)prepareInstrument:(ScoreInstrumentDefinition *)instrument error:(NSError **)error;
@end

@interface ScoreInstrumentRegistry : NSObject
{
  NSMutableDictionary *_backends;
}
+ (ScoreInstrumentRegistry *)sharedRegistry;
- (void)registerBackend:(id<ScoreInstrumentBackend>)backend;
- (id<ScoreInstrumentBackend>)backendForIdentifier:(NSString *)identifier;
@end

@interface ScoreSynthesisCompiler : NSObject
+ (NSArray *)processingOrderForGraph:(ScoreSynthesisGraph *)graph error:(NSError **)error;
@end

@interface ScoreCompositionEvaluator : NSObject
+ (BOOL)evaluateProgram:(ScoreCompositionProgram *)program
             inDocument:(ScoreDocument *)document
                  error:(NSError **)error;
@end
