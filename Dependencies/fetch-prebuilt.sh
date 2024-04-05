#!/usr/bin/env bash

# Ensure we are in Dependencies directory
cd "$(dirname "$0")"

check_for_update() {
    if [ -f ".skip-prebuilt-fetch-$1" ]; then
        echo "Skipping prebuilt fetch for $1 since .skip-prebuilt-fetch-$1 exists. If you are developing $1 alongside SideStore, don't remove this file, or this script will replace your locally built binaries with the ones built by GitHub Actions."
        return
    fi

    if [ ! -f ".last-prebuilt-fetch-$1" ]; then
        echo "0,none" > ".last-prebuilt-fetch-$1"
    fi

    LAST_FETCH=`cat .last-prebuilt-fetch-$1 | perl -n -e '/([0-9]*),([^ ]*)$/ && print $1'`
    LAST_COMMIT=`cat .last-prebuilt-fetch-$1 | perl -n -e '/([0-9]*),([^ ]*)$/ && print $2'`

    # fetch if last fetch was over 1 hour ago
    if [[ $LAST_FETCH -lt $(expr $(date +%s) - 3600) ]] || [[ "$2" == "force" ]]; then
        echo "Checking $1 for update"
        echo
        LATEST_COMMIT=`curl https://api.github.com/repos/SideStore/$1/releases/latest | perl -n -e '/Commit: https:\\/\\/github\\.com\\/[^\\/]*\\/[^\\/]*\\/commit\\/([^"]*)/ && print $1'`
        echo
        echo "Last commit: $LAST_COMMIT"
        echo "Latest commit: $LATEST_COMMIT"
        if [[ "$LAST_COMMIT" != "$LATEST_COMMIT" ]]; then
            echo "Found update, downloading binaries"
            echo
            wget -O "$1/lib$1-sim.a" "https://github.com/SideStore/$1/releases/latest/download/lib$1-sim.a"
            if [[ "$1" != "minimuxer" ]]; then
                wget -O "$1/lib$1.a" "https://github.com/SideStore/$1/releases/latest/download/lib$1.a"
                wget -O "$1/$1.h" "https://github.com/SideStore/$1/releases/latest/download/$1.h"
                echo
            else
                wget -O "$1/lib$1-ios.a" "https://github.com/SideStore/$1/releases/latest/download/lib$1-ios.a"
                wget -O "$1/generated.zip" "https://github.com/SideStore/$1/releases/latest/download/generated.zip"
                echo
                echo "Unzipping generated.zip"
                cd "$1"
                unzip ./generated.zip
                mv -v generated/* .
                rm generated.zip
                rmdir generated/
                cd ..
                echo "Done"
            fi
        else
            echo "Up-to-date"
        fi
        echo "$(date +%s),$LATEST_COMMIT" > ".last-prebuilt-fetch-$1"
    else
        echo "It hasn't been 1 hour and force was not specified, skipping update check for $1"
    fi
}

# Allow for Xcode to check minimuxer and em_proxy separately by skipping the update check if the other one is specified as an argument
if [[ "$1" != "em_proxy" ]]; then
    check_for_update minimuxer "$1"
    if [[ "$1" != "minimuxer" ]]; then
        echo
    fi
fi
if [[ "$1" != "minimuxer" ]]; then
    check_for_update em_proxy "$1"
fi
