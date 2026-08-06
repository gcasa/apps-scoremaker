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

@interface MIDIInputManager : NSObject
{
@public
  id _target;
  SEL _action;
  SEL _changeAction;
#if defined(__APPLE__)
  unsigned int _client;
  unsigned int _inputPort;
  unsigned int _source;
  unsigned char _runningStatus;
#endif
}
- (void)setTarget:(id)target;
- (void)setAction:(SEL)action;
- (void)setChangeAction:(SEL)action;
- (NSArray *)availableSources;
- (BOOL)connectToSource:(unsigned int)source;
- (void)disconnect;
@end
