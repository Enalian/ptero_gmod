#!/bin/bash

#
# Copyright (c) 2021 Matthew Penner
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

# Give everything time to initialize for preventing SteamCMD deadlock
sleep 1

# Default the TZ environment variable to UTC.
TZ=${TZ:-UTC}
export TZ

# Set environment variable that holds the Internal Docker IP
INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

# Switch to the container's working directory
cd /home/container || exit 1

# Convert all of the "{{VARIABLE}}" parts of the command into the expected shell
# variable format of "${VARIABLE}" before evaluating the string and automatically
# replacing the values.
PARSED=$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g' | eval echo "$(cat -)")

# Helper functions
trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    echo -n "$s"
}

# Update Source Server
NOW_BETAID=$( [ -f "$HOME/.now-betaid" ] && cat "$HOME/.now-betaid" || printf %s "public" )
NOW_BETAID=$(trim "$NOW_BETAID")
if [[ "$NOW_BETAID" != "$SRCDS_BETAID" || "$AUTO_UPDATE" == "1" ]]; then
    ./steamcmd/steamcmd.sh +force_install_dir /home/container +login anonymous +app_update 4020 $( [[ -z "${SRCDS_BETAID}" ]] || printf %s "-beta ${SRCDS_BETAID}" ) $( [[ "${NEED_VALIDATE}" == "0" || -z "${NEED_VALIDATE}" ]] || printf %s "validate" ) +quit
    if [ ! -d "/home/container/garrysmod" ] && [ ! -f "/home/container/srcds_run" ] && [ ! -f "/home/container/srcds_linux" ]; then
        ./steamcmd/steamcmd.sh +@sSteamCmdForcePlatformType windows +force_install_dir /home/container +login anonymous +app_update 4020 +quit
        ./steamcmd/steamcmd.sh +@sSteamCmdForcePlatformType linux +force_install_dir /home/container +login anonymous +app_update 4020 validate +quit
    fi
    printf %s "$SRCDS_BETAID" > $HOME/.now-betaid
fi

# Fix permissions
chmod 755 ~/garrysmod
chmod 755 ~/garrysmod/*

# GitHub integration
if [ "${GITHUB_ENABLED}" == "1" ]; then
    # Get repo url
    GITHUB_DEFAULT_PROTO=$( [[ $GITHUB_PROTO == "ssh" ]] && printf %s 'git@github.com:' || printf %s 'https://github.com/' )
    GITHUB_REPO_URL_PROTO=$( [[ $GITHUB_REPO == https://github.com/* ]] || printf %s $GITHUB_DEFAULT_PROTO )
    if [[ $GITHUB_REPO == git@github.com:* ]]; then
        GITHUB_REPO_URL_PROTO=""
    fi
    GITHUB_REPO_URL_EXT=$( [[ $GITHUB_REPO == *.git ]] || printf %s '.git' )
    GITHUB_REPO_URL=$GITHUB_REPO_URL_PROTO$GITHUB_REPO$GITHUB_REPO_URL_EXT

    # GitHub auth
    if [ $GITHUB_PROTO == "https" ] && [ -n "$GITHUB_LOGIN" ] && [ -n "$GITHUB_PASSWORD" ]; then
        git config --global credential.helper store
        echo "https://${GITHUB_LOGIN}:${GITHUB_PASSWORD}@github.com" > ~/.git-credentials
    fi

    # Fix directory permissions
    SSH_DIR="$HOME/.ssh"
    if [ -d "$SSH_DIR" ]; then
        chmod 700 "$SSH_DIR"

        # Fix all key permissions
        chmod 600 "$SSH_DIR"/*
        chmod 644 "$SSH_DIR"/*.pub

        # Fix special files permissions
        if [ -f "$SSH_DIR/known_hosts" ]; then
            chmod 644 "$SSH_DIR/known_hosts"
        fi
        if [ -f "$SSH_DIR/config" ]; then
            chmod 644 "$SSH_DIR/config"
        fi
    fi

    if [ ! -d ".git-tmp" ]; then
        mkdir .git-tmp
    fi
    cd .git-tmp

    if [ -d ".git" ]; then
        if [ "$(git remote get-url origin)" != "${GITHUB_REPO_URL}" ]; then
            cd ..
            rm -rf .git-tmp
            mkdir .git-tmp
            cd .git-tmp
        else
            rm -f .git/index.lock
        fi
    fi

    if [ ! -d ".git" ]; then
        git init
        git remote add origin "$GITHUB_REPO_URL"
    fi

    git fetch origin

    if [ -n "$GITHUB_BRANCH" ]; then
        BRANCH_CHECK=$(git ls-remote --heads "$GITHUB_REPO_URL" "$GITHUB_BRANCH")
        if [ -n "$BRANCH_CHECK" ]; then
            TARGET_BRANCH="$GITHUB_BRANCH"
        fi
    fi

    if [ -z "$TARGET_BRANCH" ]; then
        git remote set-head origin -a > /dev/null 2>&1
        TARGET_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's@origin/@@')
        TARGET_BRANCH="${TARGET_BRANCH:-main}"
    fi

    git checkout -q "$TARGET_BRANCH"
    git pull origin "$TARGET_BRANCH"
    git reset --hard "origin/$TARGET_BRANCH"
    git clean -fd

    cd ..
    pgit-clone .git-tmp garrysmod -s
fi

# Display the command we're running in the output, and then execute it with the env
# from the container itself.
printf "\033[1m\033[33mcontainer@%s:~# \033[0m%s\n" "$P_SERVER_UUID" "$PARSED"
# shellcheck disable=SC2086
exec env ${PARSED}