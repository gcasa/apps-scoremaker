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

/**
 * Enumerates MIDI input endpoints, maintains one active connection, and sends
 * decoded channel messages to an Objective-C target/action pair.
 */
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

/** Sets the nonretained receiver of decoded MIDI messages. */
- (void)setTarget:(id)target;

/** Sets the selector invoked for decoded MIDI messages. */
- (void)setAction:(SEL)action;

/** Sets the selector invoked when the endpoint list changes. */
- (void)setChangeAction:(SEL)action;

/** Returns dictionaries describing currently available input endpoints. */
- (NSArray *)availableSources;

/** Connects to the platform endpoint represented by <var>source</var>. */
- (BOOL)connectToSource:(unsigned int)source;

/** Disconnects the active endpoint and clears parser state. */
- (void)disconnect;
@end
