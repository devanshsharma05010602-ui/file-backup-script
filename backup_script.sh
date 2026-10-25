#!/bin/bash
#
# backup_script.sh - Automated incremental + compressed file backup
#
# Usage:   ./backup_script.sh [-c] [-k N] <source_directory> <destination_directory>
#
#   -c      also create a compressed tar.bz2 archive of each backup
#   -k N    number of backups to keep (default: 5); older ones are deleted
#   -h      show help
#
# How it works:
#   1. rsync copies source -> <dest>/backup_<timestamp>/
#      Unchanged files are hard-linked (--link-dest) to the previous backup,
#      so they share the same inode and take no extra disk space.
#   2. A symlink <dest>/latest always points to the newest backup.
#   3. (optional, -c) tar + bzip2 creates <dest>/archives/backup_<timestamp>.tar.bz2
#   4. Rotation removes the oldest backups beyond the -k limit.
#   5. Every step is logged to ./log/backup.log (next to this script).

set -uo pipefail

KEEP=5
COMPRESS=0

usage() {
    echo "Usage: $0 [-c] [-k N] <source_directory> <destination_directory>"
    echo "  -c    also create a compressed tar.bz2 archive"
    echo "  -k N  number of backups to keep (default: 5)"
    exit 1
}

# ---------- 1. Parse options and check parameters ----------
while getopts ":ck:h" opt; do
    case "$opt" in
        c) COMPRESS=1 ;;
        k) KEEP="$OPTARG" ;;
        h|*) usage ;;
    esac
done
shift $((OPTIND - 1))

if [ "$#" -ne 2 ]; then
    usage
fi

if ! [[ "$KEEP" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: -k must be a positive integer."
    exit 1
fi

# ---------- 2. Validate source and destination ----------
if [ ! -d "$1" ] || [ ! -d "$2" ]; then
    echo "Error: source and destination must both be existing directories."
    exit 1
fi

source_dir="$(realpath "$1")"
destination="$(realpath "$2")"

if [ "$source_dir" = "$destination" ]; then
    echo "Error: source and destination cannot be the same directory."
    exit 1
fi

# Destination inside source would make the backup copy itself endlessly
case "$destination/" in
    "$source_dir"/*)
        echo "Error: destination cannot be inside the source directory."
        exit 1
        ;;
esac

if ! command -v rsync >/dev/null 2>&1; then
    echo "Error: rsync is not installed (sudo apt install rsync)."
    exit 1
fi

# ---------- 3. Logging ----------
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log_dir="$script_dir/log"
log_file="$log_dir/backup.log"
mkdir -p "$log_dir"

log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $message" >> "$log_file"
    echo "$message"
}

# ---------- 4. Prevent two backups running at once ----------
exec 9>"$destination/.backup.lock"
if ! flock -n 9; then
    log "ERROR: another backup is already running. Exiting."
    exit 1
fi

# ---------- 5. Backup ----------
timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
backup_dir="$destination/backup_$timestamp"
partial_dir="$backup_dir.partial"
latest_link="$destination/latest"

log "Backup started: '$source_dir' -> '$backup_dir'"

link_opt=()
if [ -L "$latest_link" ] && [ -d "$latest_link" ]; then
    link_opt=(--link-dest="$(readlink -f "$latest_link")")
fi

# --delete: files removed from source are also absent from this new snapshot
rsync -a --delete "${link_opt[@]}" "$source_dir/" "$partial_dir/"
rc=$?

# rc 24 = some files vanished while copying (harmless); anything else non-zero = failure
if [ "$rc" -ne 0 ] && [ "$rc" -ne 24 ]; then
    log "ERROR: rsync failed with exit code $rc. Backup aborted."
    rm -rf "$partial_dir"
    exit "$rc"
fi
[ "$rc" -eq 24 ] && log "WARNING: some files vanished during backup."

# Only a fully successful copy becomes a real backup
mv "$partial_dir" "$backup_dir"

# Symlink 'latest' -> newest backup (relative target, so it survives moving the folder)
ln -sfn "$(basename "$backup_dir")" "$latest_link"
log "Snapshot created. 'latest' now points to $(basename "$backup_dir")."

# ---------- 6. Optional compressed archive ----------
if [ "$COMPRESS" -eq 1 ]; then
    mkdir -p "$destination/archives"
    archive="$destination/archives/backup_$timestamp.tar.bz2"
    if tar -cjf "$archive" -C "$backup_dir" . ; then
        size="$(du -h "$archive" | cut -f1)"
        log "Compressed archive created: $archive ($size)"
    else
        log "ERROR: failed to create archive $archive"
        rm -f "$archive"
    fi
fi

# ---------- 7. Rotation: keep only the newest $KEEP backups ----------
# Names contain the timestamp, so sorting by name is reliable (file mtimes are not:
# rsync -a copies the source folder's modification time onto the backup).
rotate() {
    local pattern="$1" label="$2" count old
    count="$(ls -1d $pattern 2>/dev/null | wc -l)"
    if [ "$count" -gt "$KEEP" ]; then
        log "Performing $label rotation (found $count, keeping $KEEP)..."
        ls -1d $pattern | sort -r | tail -n +"$((KEEP + 1))" | while IFS= read -r old; do
            rm -rf -- "$old"
            log "Oldest $label '$(basename "$old")' deleted."
        done
    fi
}

rotate "$destination/backup_[0-9]*[0-9]" "backup"
if [ "$COMPRESS" -eq 1 ]; then
    rotate "$destination/archives/backup_*.tar.bz2" "archive"
fi

log "Backup completed from '$source_dir' to '$backup_dir'."
exit 0
