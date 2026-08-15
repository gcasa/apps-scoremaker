# Generate the ScoreMaker API reference with GNUstep's autogsdoc tool.

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif
ifeq ($(GNUSTEP_MAKEFILES),)
 $(error GNUstep Make is required to generate the API documentation)
endif

include $(GNUSTEP_MAKEFILES)/common.make

DOCUMENT_NAME = ScoreMaker

ScoreMaker_AGSDOC_FILES = \
../src/AppDelegate.h \
../src/EngravingLayout.h \
../src/MIDIInputManager.h \
../src/MidiParser.h \
../src/MusicEngine.h \
../src/MusicPlatformModel.h \
../src/MusicXMLParser.h \
../src/NotationModel.h \
../src/PlaybackMonitorView.h \
../src/RealtimeDSP.h \
../src/ScoreMakerDocument.h \
../src/ScoreMakerDocumentController.h \
../src/ScoreModel.h \
../src/ScoreProjectSerializer.h \
../src/ScoreView.h \
../src/ScorefileParser.h

ScoreMaker_AGSDOC_FLAGS = -MakeFrames YES
ScoreMaker_DOC_INSTALL_DIR = Developer

include $(GNUSTEP_MAKEFILES)/documentation.make
