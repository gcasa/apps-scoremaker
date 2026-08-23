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

/** Converts Standard MIDI files to and from the ScoreMaker document model. */
@interface MidiParser : NSObject

/**
 * Parses the MIDI file at <var>path</var>.
 * Returns a new score document, or <code>nil</code> and an error on failure.
 */
+ (ScoreDocument *)parseFileAtPath:(NSString *)path error:(NSError **)error;

/**
 * Encodes <var>document</var> as a Standard MIDI file.
 * Returns the encoded bytes, or <code>nil</code> and an error on failure.
 */
+ (NSData *)dataForDocument:(ScoreDocument *)document error:(NSError **)error;

/** Returns the ordered list of 128 General MIDI program names. */
+ (NSArray *)generalMidiProgramNames;

/**
 * Parses a Cakewalk instrument-definition (.ins) file. Each returned dictionary contains
 * a name and an ordered banks array; each bank contains number, name, and a 128-entry patches
 * array. Missing patch names are represented by NSNull.
 */
+ (NSArray *)instrumentDefinitionsFromINSFileAtPath:(NSString *)path error:(NSError **)error;

+ (NSArray *)instrumentDefinitionsFromINSString:(NSString *)contents error:(NSError **)error;
@end
