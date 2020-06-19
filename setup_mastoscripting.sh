#!/bin/sh

# Global variables to be set
MASTODONUSER='mastodon'
_MASTODONDIR="$HOME/live"

# Exit function
_exit() {
    unset _exit
    unset MASTODONUSER
    if [ $1 -ne 0 ]; then
        echo "$0: $2"
        unset _MASTODONDIR
        exit $1
    fi
}

# Ensure correct user
[ "$HOME" = "/home/$MASTODONUSER" ] || _exit 1 'Running as incorrect user'

# Ensure path set and rbenv executable
if ! echo "$PATH" | grep -q "$HOME/.rbenv/bin"; then
    [ -d "$HOME/.rbenv" ] && _exit 1 'No rbenv, wut?'
    "$HOME/.rbenv/bin/rbenv" --version > /dev/null 2>&1 || _exit 1 'Cannot execute rbenv!'
    export PATH="$HOME/.rbenv/bin:$PATH"
fi

# Ensure rbenv setup
(type 'rbenv' | grep 'function') > /dev/null 2>&1 || eval "$(rbenv init -)"

# Execute tootctl properly
_tootctl() {
    (cd "$_MASTODONDIR" > /dev/null 2>&1 && RAILS_ENV=production bundle exec bin/tootctl $@)
}

_exit 0
