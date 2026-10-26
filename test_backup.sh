#!/usr/bin/env bash
# Small integration test. Creates temporary folders and removes them on exit.
set -Eeuo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/source" "$tmp/destination"
printf 'first file\n' > "$tmp/source/hello.txt"
"$project_dir/backup_script.sh" -c -k 2 "$tmp/source" "$tmp/destination"
[[ -f "$tmp/destination/latest/hello.txt" ]]
[[ -L "$tmp/destination/latest" ]]
archive=$(find "$tmp/destination/archives" -type f -name '*.tar.bz2' -print -quit)
[[ -n "$archive" ]]
mkdir "$tmp/restore"
tar -xjf "$archive" -C "$tmp/restore"
cmp "$tmp/source/hello.txt" "$tmp/restore/hello.txt"
printf 'second file\n' > "$tmp/source/second.txt"
sleep 1
"$project_dir/backup_script.sh" -k 2 "$tmp/source" "$tmp/destination"
[[ -f "$tmp/destination/latest/second.txt" ]]
printf '\nPASS: snapshot, latest link, archive restore, and second backup verified.\n'
