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

/** Error user-info key containing the failing source range as an NSValue. */
extern NSString *const ScorefileErrorRangeKey;
/** Error user-info key containing the one-based source line number. */
extern NSString *const ScorefileErrorLineKey;
/** Error user-info key containing the one-based source column number. */
extern NSString *const ScorefileErrorColumnKey;
/** Posted whenever a score script executes a print statement. */
extern NSString *const ScorefileConsoleDidPrintNotification;
/** Notification user-info key containing one printed line. */
extern NSString *const ScorefileConsoleLineKey;

/** Parses and writes MusicKit-compatible textual scorefiles. */
@interface ScorefileParser : NSObject

/** Returns all text emitted by script print statements in this process. */
+ (NSString *)consoleOutput;

/** Removes all text previously emitted by script print statements. */
+ (void)clearConsoleOutput;

/** Parses the scorefile at <var>path</var>, returning <code>nil</code> on failure. */
+ (ScoreDocument *)parseFileAtPath:(NSString *)path error:(NSError **)error;

/**
 * Parses <var>source</var> and uses <var>title</var> when the source does not
 * supply a title. Returns <code>nil</code> and a ranged error on failure.
 */
+ (ScoreDocument *)parseString:(NSString *)source
                suggestedTitle:(NSString *)title
                         error:(NSError **)error;

/**
 * Parses source and optionally returns note-to-source mappings in
 * <var>noteRanges</var>. Each mapping identifies a parsed note and its range.
 */
+ (ScoreDocument *)parseString:(NSString *)source
                suggestedTitle:(NSString *)title
              noteSourceRanges:(NSArray **)noteRanges
                         error:(NSError **)error;

/** Returns the MusicKit-compatible UTF-8 representation of <var>document</var>. */
+ (NSData *)dataForDocument:(ScoreDocument *)document error:(NSError **)error;

/** Atomically writes <var>document</var> to <var>path</var>. */
+ (BOOL)writeDocument:(ScoreDocument *)document
         toFileAtPath:(NSString *)path
                error:(NSError **)error;
@end
