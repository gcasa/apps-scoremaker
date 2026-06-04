ifeq ($(GNUSTEP_MAKEFILES),)
include Makefile
else

include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = ScoreMaker

ScoreMaker_OBJC_FILES = \
	src/main.m \
	src/AppDelegate.m \
	src/ScoreMakerDocumentController.m \
	src/MidiParser.m \
	src/ScorefileParser.m \
	src/ScoreModel.m \
	src/ScoreMakerDocument.m \
	src/ScoreView.m

ScoreMaker_HEADER_FILES = \
	src/AppDelegate.h \
	src/ScoreMakerDocumentController.h \
	src/MidiParser.h \
	src/ScorefileParser.h \
	src/ScoreModel.h \
	src/ScoreMakerDocument.h \
	src/ScoreView.h

ScoreMaker_RESOURCE_FILES = \
	Resources/bass_clef.png \
	Resources/ScoreMakerAppIcon.icns \
	Resources/ScoreMakerAppIcon.png \
	Resources/ScoreMakerDocumentIcon.icns \
	Resources/ScoreMakerDocumentIcon.png \
	Resources/treble_clef.png

ScoreMaker_APPLICATION_ICON = ScoreMakerAppIcon.png

include $(GNUSTEP_MAKEFILES)/application.make

endif
