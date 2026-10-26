#!/usr/bin/env bash
# File Backup Script: timestamped rsync snapshots, optional compressed archives,
# logging, lock protection, and automatic retention.
set -Eeuo pipefail

KEEP=5
COMPRESS=0

usage() {
  cat <<USAGE
Usage: $0 [-c] [-k N] SOURCE_DIRECTORY DESTINATION_DIRECTORY
  -c    Create a compressed .tar.bz2 archive as well as the snapshot
  -k N  Number of snapshots (and archives, when -c is used) to retain; default: 5
  -h    Show this help
USAGE
}
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

while getopts ':ck:h' opt; do
  case "$opt" in
    c) COMPRESS=1 ;;
    k) KEEP=$OPTARG ;;
    h) usage; exit 0 ;;
    :) fail "option -$OPTARG requires a value" ;;
    \?) fail "unknown option: -$OPTARG (use -h for help)" ;;
  esac
done
shift $((OPTIND - 1))
[[ $# -eq 2 ]] || { usage >&2; exit 2; }
[[ "$KEEP" =~ ^[1-9][0-9]*$ ]] || fail "-k must be a positive integer."

install_hint() {
  if command -v dnf >/dev/null 2>&1; then echo 'sudo dnf install rsync tar bzip2 util-linux'
  elif command -v yum >/dev/null 2>&1; then echo 'sudo yum install rsync tar bzip2 util-linux'
  else echo 'sudo apt install rsync tar bzip2 util-linux'; fi
}
for cmd in rsync tar bzip2 realpath flock; do
  command -v "$cmd" >/dev/null 2>&1 || fail "'$cmd' is required. Install it with: $(install_hint)"
done
[[ -d "$1" ]] || fail "source directory does not exist: $1"
[[ -d "$2" ]] || fail "destination directory must already exist: $2"
source_dir=$(realpath "$1")
destination=$(realpath "$2")
[[ "$source_dir" != "$destination" ]] || fail 'source and destination cannot be the same directory.'
case "$destination/" in "$source_dir/"*) fail 'destination cannot be inside the source directory.';; esac
case "$source_dir/" in "$destination/"*) fail 'source cannot be inside the destination directory.';; esac

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
log_dir="$script_dir/log"
mkdir -p -- "$log_dir"
log_file="$log_dir/backup.log"
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$log_file"; }

# Lock file stays in the destination so cron and manual runs share the same lock.
exec 9>"$destination/.backup.lock"
flock -n 9 || { log 'ERROR: another backup is already running; exiting.'; exit 1; }

timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
backup_dir="$destination/backup_$timestamp"
partial_dir="$destination/.backup_$timestamp.partial"
latest_link="$destination/latest"
[[ ! -e "$backup_dir" && ! -e "$partial_dir" ]] || fail 'a backup with this timestamp already exists; wait one second and retry.'

log "Starting backup: '$source_dir' -> '$backup_dir'"
link_opt=()
if [[ -L "$latest_link" && -d "$latest_link" ]]; then
  previous=$(realpath "$latest_link")
  # Only reuse a previous snapshot that is directly inside this destination.
  case "$previous" in "$destination"/backup_*) link_opt=(--link-dest="$previous");; esac
fi

set +e
rsync -a --delete "${link_opt[@]}" -- "$source_dir/" "$partial_dir/"
rsync_rc=$?
set -e
if [[ $rsync_rc -ne 0 && $rsync_rc -ne 24 ]]; then
  log "ERROR: rsync failed (exit $rsync_rc); removing incomplete snapshot."
  rm -rf -- "$partial_dir"
  exit "$rsync_rc"
fi
[[ $rsync_rc -ne 24 ]] || log 'WARNING: some source files vanished while copying; snapshot may be incomplete.'
mv -- "$partial_dir" "$backup_dir"
ln -sfn -- "$(basename -- "$backup_dir")" "$latest_link"
log "Snapshot created; latest -> $(basename -- "$backup_dir")."

if [[ $COMPRESS -eq 1 ]]; then
  archive_dir="$destination/archives"
  mkdir -p -- "$archive_dir"
  archive="$archive_dir/backup_$timestamp.tar.bz2"
  if tar -cjf "$archive" -C "$backup_dir" .; then
    log "Compressed archive created: $archive ($(du -h "$archive" | cut -f1))."
  else
    rm -f -- "$archive"
    log "ERROR: archive creation failed: $archive"
    exit 1
  fi
fi

# Rotation uses find + NUL-delimited paths, so directory names with spaces work.
rotate_snapshots() {
  local -a items=()
  mapfile -d '' -t items < <(find "$destination" -mindepth 1 -maxdepth 1 -type d -name 'backup_[0-9]*' -print0 | sort -z -r)
  if (( ${#items[@]} > KEEP )); then
    log "Snapshot rotation: found ${#items[@]}, retaining $KEEP."
    for ((i=KEEP; i<${#items[@]}; i++)); do
      [[ "${items[i]}" == "$backup_dir" ]] && continue
      rm -rf -- "${items[i]}"
      log "Deleted old snapshot: $(basename -- "${items[i]}")"
    done
  fi
}
rotate_archives() {
  local -a items=()
  [[ -d "$destination/archives" ]] || return 0
  mapfile -d '' -t items < <(find "$destination/archives" -maxdepth 1 -type f -name 'backup_*.tar.bz2' -print0 | sort -z -r)
  if (( ${#items[@]} > KEEP )); then
    log "Archive rotation: found ${#items[@]}, retaining $KEEP."
    for ((i=KEEP; i<${#items[@]}; i++)); do
      rm -f -- "${items[i]}"
      log "Deleted old archive: $(basename -- "${items[i]}")"
    done
  fi
}
rotate_snapshots
if [[ $COMPRESS -eq 1 ]]; then rotate_archives; fi
log "Backup completed successfully: '$backup_dir'."
