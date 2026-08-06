ifeq ($(GNUSTEP_MAKEFILES),)
include Makefile
else

# Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
#
# This file is part of ScoreMaker.
#
# ScoreMaker is free software: you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 2.1 of the License, or (at
# your option) any later version.
#
# ScoreMaker is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
# License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with ScoreMaker.  If not, see <https://www.gnu.org/licenses/>.

include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = ScoreMaker

ScoreMaker_OBJC_FILES = \
	src/RealtimeDSP.m \
	src/main.m \
	src/AppDelegate.m \
	src/ScoreMakerDocumentController.m \
	src/MidiParser.m \
	src/MusicXMLParser.m \
	src/ScorefileParser.m \
	src/ScoreProjectSerializer.m \
	src/ScoreModel.m \
	src/MusicPlatformModel.m \
	src/MusicEngine.m \
	src/ScoreMakerDocument.m \
	src/ScoreView.m \
	src/PlaybackMonitorView.m \
	src/MIDIInputManager.m

ScoreMaker_HEADER_FILES = \
	src/RealtimeDSP.h \
	src/AppDelegate.h \
	src/ScoreMakerDocumentController.h \
	src/MidiParser.h \
	src/MusicXMLParser.h \
	src/ScorefileParser.h \
	src/ScoreProjectSerializer.h \
	src/ScoreModel.h \
	src/MusicPlatformModel.h \
	src/MusicEngine.h \
	src/ScoreMakerDocument.h \
	src/ScoreView.h \
	src/PlaybackMonitorView.h \
	src/MIDIInputManager.h

ScoreMaker_RESOURCE_FILES = \
	Resources/bass_clef.png \
	Resources/ScoreMakerAppIcon.icns \
	Resources/ScoreMakerAppIcon.png \
	Resources/ScoreMakerDocumentIcon.icns \
	Resources/ScoreMakerDocumentIcon.png \
	Resources/treble_clef.png

ScoreMaker_APPLICATION_ICON = ScoreMakerAppIcon.png

ADDITIONAL_LDFLAGS = -lAVFoundation

include $(GNUSTEP_MAKEFILES)/application.make

.PHONY: run
run:: all
	openapp ./$(APP_NAME).app

endif
