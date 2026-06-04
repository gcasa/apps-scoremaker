APP_NAME := ScoreMaker
BUILD_DIR := build
SRC_DIR := src
SOURCES := $(SRC_DIR)/main.m $(SRC_DIR)/AppDelegate.m $(SRC_DIR)/MidiParser.m $(SRC_DIR)/ScorefileParser.m $(SRC_DIR)/ScoreModel.m $(SRC_DIR)/ScoreView.m

UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
CC := clang
CFLAGS := -Wall -Wextra -Werror -fobjc-exceptions -fconstant-string-class=NSConstantString
LDFLAGS := -framework Cocoa
APP_DIR := $(BUILD_DIR)/macos/$(APP_NAME).app
APP_BIN := $(APP_DIR)/Contents/MacOS/$(APP_NAME)

.PHONY: all clean run
all: $(APP_BIN)

$(APP_BIN): $(SOURCES) Info.plist
	mkdir -p "$(APP_DIR)/Contents/MacOS"
	mkdir -p "$(APP_DIR)/Contents/Resources"
	cp Info.plist "$(APP_DIR)/Contents/Info.plist"
	$(CC) $(CFLAGS) $(SOURCES) $(LDFLAGS) -o "$@"

run: $(APP_BIN)
	open "$(APP_DIR)"

else
GNUSTEP_CONFIG := gnustep-config
GNUSTEP_CFLAGS := $(shell $(GNUSTEP_CONFIG) --objc-flags)
GNUSTEP_LIBS := $(shell $(GNUSTEP_CONFIG) --gui-libs)
APP_BIN := $(BUILD_DIR)/gnustep/$(APP_NAME)

.PHONY: all clean run
all: $(APP_BIN)

$(APP_BIN): $(SOURCES)
	mkdir -p "$(BUILD_DIR)/gnustep"
	$(CC) $(GNUSTEP_CFLAGS) -Wall -Wextra -fobjc-exceptions $(SOURCES) $(GNUSTEP_LIBS) -o "$@"

run: $(APP_BIN)
	"$(APP_BIN)"
endif

clean:
	rm -rf "$(BUILD_DIR)"
