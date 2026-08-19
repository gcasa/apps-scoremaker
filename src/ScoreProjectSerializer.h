/*
 * Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 *
 * This file is part of ScoreMaker.
 * ScoreMaker is distributed under the GNU Lesser General Public License 2.1 or later.
 */

#import <Foundation/Foundation.h>
#import "ScoreModel.h"

/** Reads and writes ScoreMaker's native project container format. */
@interface ScoreProjectSerializer : NSObject
/**
 * Serializes <var>document</var>, including platform-specific state, into a
 * native project container. Returns <code>nil</code> on failure.
 */
+ (NSData *)dataForDocument:(ScoreDocument *)document error:(NSError **)error;
/**
 * Restores a score document from native project <var>data</var>.
 * Returns <code>nil</code> when the data is damaged or unsupported.
 */
+ (ScoreDocument *)documentFromData:(NSData *)data error:(NSError **)error;
@end
