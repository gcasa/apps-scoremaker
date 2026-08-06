/*
 * Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 *
 * This file is part of ScoreMaker.
 * ScoreMaker is distributed under the GNU Lesser General Public License 2.1 or later.
 */

#import <Foundation/Foundation.h>
#import "ScoreModel.h"

@interface ScoreProjectSerializer : NSObject
+ (NSData *)dataForDocument:(ScoreDocument *)document error:(NSError **)error;
+ (ScoreDocument *)documentFromData:(NSData *)data error:(NSError **)error;
@end
