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

/** Converts uncompressed MusicXML files to and from ScoreMaker documents. */
@interface MusicXMLParser : NSObject
/**
 * Parses the MusicXML file at <var>path</var>.
 * Returns a new score document, or <code>nil</code> and an error on failure.
 */
+ (ScoreDocument *)parseFileAtPath:(NSString *)path error:(NSError **)error;
/**
 * Encodes <var>document</var> as uncompressed MusicXML data.
 * Returns <code>nil</code> and an error if serialization fails.
 */
+ (NSData *)dataForDocument:(ScoreDocument *)document error:(NSError **)error;
@end
