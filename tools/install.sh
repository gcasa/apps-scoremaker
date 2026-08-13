#!/bin/sh

set -eu

case "$(uname -s)" in
    Darwin)
        make -f Makefile clean
        make -f Makefile
        app_path=build/macos/ScoreMaker.app
        install_dir=${1:-/Users/Shared/Local/Demos}
        ;;
    *)
        if ! command -v gnustep-config >/dev/null 2>&1; then
            echo "error: gnustep-config is required for non-Darwin builds" >&2
            exit 1
        fi

        make -f GNUmakefile clean
        make -f GNUmakefile
        app_path=ScoreMaker.app
        install_dir=${1:-$(gnustep-config --variable=GNUSTEP_LOCAL_APPS)}
        ;;
esac

if [ -z "$install_dir" ]; then
    echo "error: could not determine the application install directory" >&2
    exit 1
fi

mkdir -p "$install_dir"
rm -rf "$install_dir/ScoreMaker.app"
cp -R "$app_path" "$install_dir/ScoreMaker.app"

echo "Installed ScoreMaker.app in $install_dir"
