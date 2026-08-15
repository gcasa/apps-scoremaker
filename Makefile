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

APP_NAME := ScoreMaker
BUILD_DIR := build
SRC_DIR := src
SOURCES := $(SRC_DIR)/RealtimeDSP.m $(SRC_DIR)/main.m $(SRC_DIR)/AppDelegate.m $(SRC_DIR)/ScoreMakerDocumentController.m $(SRC_DIR)/ScoreMakerDocument.m $(SRC_DIR)/MidiParser.m $(SRC_DIR)/MusicXMLParser.m $(SRC_DIR)/ScorefileParser.m $(SRC_DIR)/ScoreProjectSerializer.m $(SRC_DIR)/ScoreModel.m $(SRC_DIR)/MusicPlatformModel.m $(SRC_DIR)/MusicEngine.m $(SRC_DIR)/NotationModel.m $(SRC_DIR)/EngravingLayout.m $(SRC_DIR)/ScoreView.m $(SRC_DIR)/PlaybackMonitorView.m $(SRC_DIR)/MIDIInputManager.m
RESOURCE_FILES := Resources/treble_clef.png Resources/bass_clef.png Resources/ScoreMakerAppIcon.icns Resources/ScoreMakerDocumentIcon.icns

UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
CC := clang
CFLAGS := -Wall -Wextra -fobjc-exceptions -fconstant-string-class=NSConstantString
LDFLAGS := -framework Cocoa -framework AVFoundation -framework AudioToolbox -framework CoreAudioKit -framework CoreMIDI
APP_DIR := $(BUILD_DIR)/macos/$(APP_NAME).app
APP_BIN := $(APP_DIR)/Contents/MacOS/$(APP_NAME)

.PHONY: all clean run release test test-plugins
all: $(APP_BIN)

$(APP_BIN): $(SOURCES) Info.plist $(RESOURCE_FILES)
	mkdir -p "$(APP_DIR)/Contents/MacOS"
	mkdir -p "$(APP_DIR)/Contents/Resources"
	cp Info.plist "$(APP_DIR)/Contents/Info.plist"
	cp $(RESOURCE_FILES) "$(APP_DIR)/Contents/Resources/"
	$(CC) $(CFLAGS) $(SOURCES) $(LDFLAGS) -o "$@"

run: $(APP_BIN)
	open "$(APP_DIR)"

release:
	$(MAKE) BUILD_DIR=build/release CFLAGS="-Wall -Wextra -O2 -DNDEBUG -fobjc-exceptions -fconstant-string-class=NSConstantString"

test: $(APP_BIN)
	mkdir -p "$(BUILD_DIR)/tests"
	$(CC) $(CFLAGS) -Isrc tests/ScorefileCompatibilityTests.m src/RealtimeDSP.m src/ScorefileParser.m src/ScoreProjectSerializer.m src/MusicXMLParser.m src/MidiParser.m src/ScoreModel.m src/MusicPlatformModel.m src/MusicEngine.m src/NotationModel.m src/EngravingLayout.m -framework Foundation -framework AppKit -framework AVFoundation -framework AudioToolbox -framework CoreAudioKit -o "$(BUILD_DIR)/tests/scorefile-tests"
	"$(BUILD_DIR)/tests/scorefile-tests"

test-plugins:
	mkdir -p "$(BUILD_DIR)/tests"
	python3 tools/test-audio-units.py > "$(BUILD_DIR)/tests/audio-unit-compatibility.json"

else
CC := clang
GNUSTEP_CONFIG := gnustep-config
GNUSTEP_CFLAGS := $(shell $(GNUSTEP_CONFIG) --objc-flags)
GNUSTEP_LIBS := $(shell $(GNUSTEP_CONFIG) --gui-libs)
GNUSTEP_AVFOUNDATION_LIBS := -lAVFoundation
APP_BIN := $(BUILD_DIR)/gnustep/$(APP_NAME)

.PHONY: all clean run release test
all: $(APP_BIN)

$(APP_BIN): $(SOURCES)
	mkdir -p "$(BUILD_DIR)/gnustep"
	$(CC) $(GNUSTEP_CFLAGS) -Wall -Wextra -fobjc-exceptions $(SOURCES) $(GNUSTEP_LIBS) $(GNUSTEP_AVFOUNDATION_LIBS) -o "$@"

run: $(APP_BIN)
	"$(APP_BIN)"

release:
	$(MAKE) BUILD_DIR=build/release

test: $(APP_BIN)
	mkdir -p "$(BUILD_DIR)/tests"
	$(CC) $(GNUSTEP_CFLAGS) -Wall -Wextra -fobjc-exceptions -Isrc tests/ScorefileCompatibilityTests.m src/RealtimeDSP.m src/ScorefileParser.m src/ScoreProjectSerializer.m src/MusicXMLParser.m src/MidiParser.m src/ScoreModel.m src/MusicPlatformModel.m src/MusicEngine.m src/NotationModel.m src/EngravingLayout.m $(GNUSTEP_LIBS) $(GNUSTEP_AVFOUNDATION_LIBS) -o "$(BUILD_DIR)/tests/scorefile-tests"
	"$(BUILD_DIR)/tests/scorefile-tests"
endif

clean:
	rm -rf "$(BUILD_DIR)"
