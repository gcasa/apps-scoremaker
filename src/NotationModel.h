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

typedef NS_ENUM (NSInteger, ScoreNotationKind) {
  ScoreNotationNote,
  ScoreNotationRest,
  ScoreNotationAccidental,
  ScoreNotationSlur,
  ScoreNotationTie,
  ScoreNotationTuplet,
  ScoreNotationDynamic,
  ScoreNotationArticulation,
  ScoreNotationKeySignature,
  ScoreNotationRepeat
};

/* A normalized semantic element. Importers and editors may continue using the
 * compatibility fields on ScoreNote/ScoreMeasure; all downstream consumers
 * should use this representation instead of interpreting those fields again. */
@interface ScoreNotationElement : NSObject
{
  ScoreNotationKind _kind;
  NSUInteger _startTick;
  NSUInteger _endTick;
  NSInteger _track;
  NSInteger _notationVoice;
  NSString *_value;
  id _source;
}
@property (nonatomic) ScoreNotationKind kind;
@property (nonatomic) NSUInteger startTick;
@property (nonatomic) NSUInteger endTick;
@property (nonatomic) NSInteger track;
@property (nonatomic) NSInteger notationVoice;
@property (nonatomic, copy) NSString *value;
@property (nonatomic, assign) id source;
@end

@interface ScoreNotationModel : NSObject
+ (NSArray *)elementsForDocument:(ScoreDocument *)document;
@end
