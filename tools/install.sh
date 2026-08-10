#!/bin/sh

make -f Makefile clean && make -f Makefile

rm -rf /Users/Shared/Local/Demos/ScoreMaker.app
cp -r ./build/macos/ScoreMaker.app /Users/Shared/Local/Demos

exit 0
