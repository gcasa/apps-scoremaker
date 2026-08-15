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

/** Identifies the musical meaning of a normalized notation element. */
typedef NS_ENUM (NSInteger, ScoreNotationKind) {
  /** A sounding note. */
  ScoreNotationNote,
  /** A notated rest. */
  ScoreNotationRest,
  /** An accidental glyph. */
  ScoreNotationAccidental,
  /** A slur span. */
  ScoreNotationSlur,
  /** A tie span. */
  ScoreNotationTie,
  /** A tuplet span or marker. */
  ScoreNotationTuplet,
  /** A dynamic marking. */
  ScoreNotationDynamic,
  /** An articulation marking. */
  ScoreNotationArticulation,
  /** A key-signature change. */
  ScoreNotationKeySignature,
  /** A repeat barline. */
  ScoreNotationRepeat
};

/**
 * A normalized semantic element. Importers and editors may continue using the
 * compatibility fields on ScoreNote and ScoreMeasure; downstream consumers
 * should use this representation instead of interpreting those fields again.
 */
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
/** Semantic kind of this element. */
@property (nonatomic) ScoreNotationKind kind;
/** Inclusive starting tick. */
@property (nonatomic) NSUInteger startTick;
/** Exclusive ending tick. */
@property (nonatomic) NSUInteger endTick;
/** Legacy track containing the element. */
@property (nonatomic) NSInteger track;
/** One-based notation voice number. */
@property (nonatomic) NSInteger notationVoice;
/** Kind-specific normalized textual value. */
@property (nonatomic, copy) NSString *value;
/** Nonretained ScoreNote or ScoreMeasure from which the element was derived. */
@property (nonatomic, assign) id source;
@end

/** Produces normalized notation elements from a complete score document. */
@interface ScoreNotationModel : NSObject
/** Returns the ordered normalized notation elements for <var>document</var>. */
+ (NSArray *)elementsForDocument:(ScoreDocument *)document;
@end
