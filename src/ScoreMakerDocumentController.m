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

#import "ScoreMakerDocumentController.h"
#import "ScoreMakerDocument.h"

static NSString *const ScoreMakerScorefileType = @"MusicKit Scorefile";
static NSString *const ScoreMakerMidiType = @"MIDI File";
static NSString *const ScoreMakerMusicXMLType = @"MusicXML File";

@implementation ScoreMakerDocumentController

- (NSString *)defaultType
{
  return ScoreMakerScorefileType;
}

- (NSArray *)documentClassNames
{
  return [NSArray arrayWithObject:@"ScoreMakerDocument"];
}

- (Class)documentClassForType:(NSString *)type
{
  if ([type isEqualToString:ScoreMakerScorefileType] || [type isEqualToString:ScoreMakerMidiType] ||
      [type isEqualToString:ScoreMakerMusicXMLType])
    {
      return [ScoreMakerDocument class];
    }
  return Nil;
}

- (NSString *)typeFromFileExtension:(NSString *)fileExtension
{
  NSString *extension = [fileExtension lowercaseString];
  if ([extension isEqualToString:@"score"])
    {
      return ScoreMakerScorefileType;
    }
  if ([extension isEqualToString:@"mid"] || [extension isEqualToString:@"midi"])
    {
      return ScoreMakerMidiType;
    }
  if ([extension isEqualToString:@"musicxml"] || [extension isEqualToString:@"xml"])
    {
      return ScoreMakerMusicXMLType;
    }
  return nil;
}

- (NSArray *)fileExtensionsFromType:(NSString *)type
{
  if ([type isEqualToString:ScoreMakerScorefileType])
    {
      return [NSArray arrayWithObject:@"score"];
    }
  if ([type isEqualToString:ScoreMakerMidiType])
    {
      return [NSArray arrayWithObjects:@"mid", @"midi", nil];
    }
  if ([type isEqualToString:ScoreMakerMusicXMLType])
    {
      return [NSArray arrayWithObjects:@"musicxml", @"xml", nil];
    }
  return [NSArray array];
}

- (NSString *)displayNameForType:(NSString *)type
{
  if ([type isEqualToString:ScoreMakerScorefileType] || [type isEqualToString:ScoreMakerMidiType] ||
      [type isEqualToString:ScoreMakerMusicXMLType])
    {
      return type;
    }
  return [super displayNameForType:type];
}

@end
