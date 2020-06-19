#!/bin/sh

set -e

# Here you should manually set your
# setup_environment.sh script location
. "/home/mastodon/live/setup_mastoscripting.sh"

# Here you can set your preferences
BACKUPDIR="${HOME}/.backup"
ARCHIVDIR="${HOME}/archives"
MEDIADAYS=14
MASTODONDB='mastodon_production'
BACKUPFREQ='12' # IN HOURS!
CLEANFREQ='14'  # IN DAYS!

# Global variables (LEAVE THESE!)
LASTBACKUP="${ARCHIVDIR}/.last_backup"
LASTCLEAN="${ARCHIVDIR}/.last_clean"

print_exit() {
    echo "$2"
    exit $1
}

set_output() {
    if [ ! -z "$1" ]; then
        if [ -f "$1" ]; then
            # Remove old
            rm -f "$1" || print_exit 1 "Failed deleting old log file: ${1}"
        fi

        touch "$1" || print_exit 1 "Failed creating log file: ${1}"
        echo "Outputting to: ${1}"

        # Close stdout
        exec 1<&-

        # Close stderr
        exec 2<&-

        # Open stdout to ${LOGFILE}
        exec 1<>"$1"

        # Redirect stderr to stdout
        exec 2>&1
    fi
}

print_if_success() {
    if [ $1 -eq 0 ]; then
        echo 'Done!'
        echo ''
    fi
}

cur_time() {
    date '+%s' || print_exit 1 'Failed getting current date!'
}

last_backup() {
    stat -c '%Z' "$LASTBACKUP" || print_exit 1 "Failed file stat on: ${LASTBACKUP}"
}

last_clean() {
    stat -c '%Z' "$LASTCLEAN" || print_exit 1 "Failed file stat on: ${LASTCLEAN}"
}

backup_freq() {
    echo $(($BACKUPFREQ * 3600)) || print_exit 1 "Invalid backup frequency string: ${BACKUPFREQ}"
}

clean_freq() {
    echo $(($CLEANFREQ * 24 * 3600))  || print_exit 1 "Invalid clean frequency string: ${CLEANFREQ}"
}

should_do_backup() {
    if [ ! -f "$LASTBACKUP" ]; then
        touch "$LASTBACKUP"
        return 0
    fi

    local cur last diff freq result
    cur=$(cur_time)
    last=$(last_backup)
    diff=$(($cur - $last))
    freq=$(backup_freq)

    if [ $diff -gt $freq ]; then
        touch "$LASTBACKUP"
        return 0
    else
        return 1
    fi
}

should_do_clean() {
    if [ ! -f "$LASTCLEAN" ]; then
        touch "$LASTCLEAN"
        return 0
    fi

    local cur last diff freq result
    cur=$(cur_time)
    last=$(last_clean)
    diff=$(($cur - $last))
    freq=$(clean_freq)

    if [ $diff -gt $freq ]; then
        touch "$LASTCLEAN"
        return 0
    else
        return 1
    fi
    
}

tootctl_execute() {
    local result

    echo "tootctl_execute: ${@}"
    _tootctl $@
    result=$?

    print_if_success $result
    return $result
}

clean_cache() {
    tootctl_execute cache clear
}

clean_media() {
    tootctl_execute media remove-orphans
    tootctl_execute media remove --days "$MEDIADAYS"
}

backup_database() {
    local result

    echo "Backing up database ${MASTODONDB}..."
    pg_dump -Fc "$MASTODONDB" > "${BACKUPDIR}/database.dump"
    result=$?

    print_if_success $result
    return $result
}

backup_live_dir() {
    local result

    echo "Performing rsync from ${_MASTODONDIR} to parallel backup dir ${BACKUPDIR}..."
    rsync --archive --times --update --delete-before "${_MASTODONDIR}" "${BACKUPDIR}"
    result=$?

    print_if_success $result
    return $result
}

create_backup_tar() {
    local result backup="${ARCHIVDIR}/backup.tar.gz"

    if [ -f "$backup" ]; then
        echo "Removing old backup tarball..."
        rm -f "$backup" || return 1
    fi

    echo "Creating gzipped tarball ${backup} from backup dir ${BACKUPDIR}..."
    tar --numeric-owner -zxcf "$backup" "${BACKUPDIR}"
    result=$?

    print_if_success $result
    return $result
}

cleanup_backupdir() {
    local result=0

    echo 'Cleaning up...'

    if [ -f "${BACKUPDIR}/database.dump" ]; then
        echo "Deleting database dump ${BACKUPDIR}/database.dump..."
        rm -f "${BACKUPDIR}/database.dump"
        result=$?
    fi

    print_if_success $result
    return $result
}

ensure_dirs() {
    mkdir -p "$ARCHIVDIR" || return 1
    mkdir -p "$BACKUPDIR" || return 1
}

mastodon_backup() {
    backup_database    || print_exit 1 'Failed backing up database!'
    backup_live_dir    || print_exit 1 'Failed backing up live dir!'
    create_backup_tar  || print_exit 1 'Failed creating backup tarball!'
    return 0
}

mastodon_clean() {
    clean_cache || echo 'Failed cleaning mastodon cache!'
    clean_media || echo 'Failed cleaning mastodon media store!'
    return 0
}

main() {
    set_output "$1"
    ensure_dirs      || print_exit 1 'Failed ensuring required dirs exist!'
    should_do_clean  && mastodon_clean
    should_do_backup && mastodon_backup
}

if [ $# -gt 1 ] || [ "$1" = '-h' ] || [ "$1" = '--help' ]; then
    echo "Usage: ${0} [log-file]"
    exit 1
fi

main "$1"
exit 0
