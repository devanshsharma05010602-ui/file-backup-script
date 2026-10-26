# Project 3 — File Backup Script (CentOS)

A Bash utility that backs up a source directory to a destination directory. It creates timestamped snapshots with `rsync`, can make compressed `.tar.bz2` archives, keeps a configurable number of recent backups, writes a log, prevents overlapping runs, and can be scheduled with `cron`.

This version is set up for **CentOS** (CentOS Stream), for example running in Oracle VirtualBox. The script itself is plain Bash and also runs on other Linux distributions.

## Features

- Timestamped, browsable backup snapshots.
- Incremental space saving with `rsync --link-dest` (unchanged files are hard-linked to the previous snapshot).
- Optional compressed archive with `tar` + `bzip2` using `-c`.
- `latest` symbolic link to the newest completed snapshot.
- Retention/rotation with `-k N` (default 5).
- Timestamped log at `log/backup.log`.
- Locking with `flock`; incomplete rsync copies are never promoted to completed snapshots.
- Input validation and a small integration test (`test_backup.sh`).

## Setup on CentOS

Use a normal user account that can run `sudo`.

1. Install the required tools. CentOS Stream and newer releases use `dnf`; on older CentOS replace `dnf` with `yum`:

   ```bash
   sudo dnf install -y rsync tar bzip2 util-linux cronie git unzip
   ```

2. Get the project, either by cloning from GitHub or by extracting the ZIP:

   ```bash
   git clone https://github.com/devanshsharma05010602-ui/file-backup-script.git
   cd file-backup-script
   ```

   or

   ```bash
   unzip file-backup-script-main.zip
   cd file-backup-script-main
   ```

3. Make the scripts executable:

   ```bash
   chmod +x backup_script.sh test_backup.sh
   ```

Tip: if the project files are on a Windows host, copy them into the VM's home folder (for example with a VirtualBox shared folder or `git clone`) and run everything from there. Avoid running scripts directly from a shared folder, because file permissions there can cause surprises.

## Requirements

CentOS (or another Linux), Bash, `rsync`, `tar`, `bzip2`, `flock` and `realpath` (both from `util-linux`/`coreutils`, installed by default), and `cronie` for scheduling.

## Quick start

Run these commands from the project directory as your normal user (not with `sudo`):

```bash
mkdir -p ~/backup-demo/source ~/backup-demo/destination
echo "My first backup file" > ~/backup-demo/source/notes.txt
./backup_script.sh -c -k 5 ~/backup-demo/source ~/backup-demo/destination
```

The destination must already exist. Expected layout:

```text
~/backup-demo/destination/
├── .backup.lock
├── backup_YYYY-MM-DD_HH-MM-SS/       # browsable snapshot
├── latest -> backup_YYYY-MM-DD_HH-MM-SS
└── archives/
    └── backup_YYYY-MM-DD_HH-MM-SS.tar.bz2
```

## Command syntax

```bash
./backup_script.sh [-c] [-k N] SOURCE_DIRECTORY DESTINATION_DIRECTORY
```

| Option | Meaning |
|---|---|
| `-c` | Create a compressed `.tar.bz2` archive as well as the snapshot |
| `-k N` | Retain the newest N snapshots and (when `-c` is used) archives; default is 5 |
| `-h` | Show help |

Examples:

```bash
# Normal snapshot
./backup_script.sh ~/Documents ~/backups/documents

# Snapshot plus compressed archive; keep last 7
./backup_script.sh -c -k 7 ~/Documents ~/backups/documents

# Help
./backup_script.sh -h
```

Create the destination directory before running. Do not use the source folder itself as the destination. The script rejects identical, nested, or non-existent source/destination directories.

## How it works

1. Validates arguments, directories, and required commands.
2. Writes a timestamped status message to `log/backup.log` and the terminal.
3. Acquires a lock so scheduled and manual backups do not overlap.
4. Uses `rsync -a --delete` to create a new snapshot in a temporary `.partial` directory. `--link-dest` reuses unchanged files from the previous snapshot.
5. Renames a successful temporary copy to a timestamped snapshot and updates `latest`.
6. If `-c` is passed, creates a `.tar.bz2` archive.
7. Deletes snapshots/archives older than the configured retention count.

**Caution:** `--delete` makes the snapshot reflect the current source, including source deletions. The script does not delete source files, but always double-check source and destination paths before running it.

## Test the project

```bash
./test_backup.sh
```

The test uses temporary folders, verifies the latest snapshot and compressed archive, extracts the archive to verify its contents, and runs a second backup. It cleans up its temporary files afterward and ends with a `PASS` message.

You can also test manually:

```bash
mkdir -p ~/backup-demo/source ~/backup-demo/destination
echo one > ~/backup-demo/source/a.txt
./backup_script.sh ~/backup-demo/source ~/backup-demo/destination
cat ~/backup-demo/destination/latest/a.txt
```

Inspect the log:

```bash
tail -n 30 log/backup.log
```

## Schedule with cron

On CentOS the cron service is called `crond` (package `cronie`). Ensure the destination exists and test the exact command manually before scheduling it.

1. Enable and start cron:

   ```bash
   sudo systemctl enable --now crond
   systemctl status crond
   ```

2. Open your user crontab:

   ```bash
   crontab -e
   ```

3. Add a line like the following, replacing `/home/YOUR_USER/...` with the real absolute paths (`echo $HOME` shows your home folder):

   ```cron
   # Every day at 5:30 PM; retain 7 snapshots
   30 17 * * * /home/YOUR_USER/file-backup-script/backup_script.sh -k 7 /home/YOUR_USER/backup-demo/source /home/YOUR_USER/backup-demo/destination >> /home/YOUR_USER/file-backup-script/cron.log 2>&1
   ```

   For a one-minute test only, use `* * * * *` temporarily, verify the log, then replace it with the daily schedule.

4. Verify the schedule:

   ```bash
   crontab -l
   tail -n 30 ~/file-backup-script/log/backup.log
   sudo grep CRON /var/log/cron      # cron's own activity log on CentOS
   ```

Cron jobs run only while the CentOS machine (or VM) is running and `crond` is active.

## Restore files

From a snapshot, copy the required file from `DESTINATION/latest/`. To extract a compressed archive:

```bash
mkdir -p ~/backup-demo/restore
tar -xjf ~/backup-demo/destination/archives/backup_YYYY-MM-DD_HH-MM-SS.tar.bz2 -C ~/backup-demo/restore
```

Replace the example archive name with an actual filename from `ls ~/backup-demo/destination/archives/`.

## Troubleshooting

- **`rsync: command not found`** — run `sudo dnf install rsync`.
- **`flock: command not found`** — run `sudo dnf install util-linux`.
- **`dnf: command not found`** — you are probably on an older CentOS; use `yum` instead of `dnf`.
- **cron does not run** — check `systemctl status crond`, run `crontab -l`, and use absolute paths.
- **`destination directory must already exist`** — create it with `mkdir -p /path/to/destination`.
- **`Permission denied`** — run the project from your home directory (`~/...`) and check file permissions with `ls -l`.

## Viva questions

1. **What is Bash?** A command interpreter used to execute shell commands and scripts.
2. **What does rsync do?** Copies and synchronizes files efficiently.
3. **What is a compressed archive?** A packaged set of files reduced in size using a compression algorithm.
4. **What is cron?** A Linux scheduler that runs commands at specified times; on CentOS the daemon is `crond`.
5. **Why use timestamps?** To distinguish backups and keep historical versions.
6. **What is a symbolic link?** A filesystem entry that points to another path; here `latest` points to the newest snapshot.
7. **Why use a lock?** To prevent simultaneous runs from modifying the same destination.

## Conclusion

The File Backup Script automates repetitive backup work by creating timestamped snapshots, optionally compressing them, maintaining a log, and removing old backups according to a retention policy. Cron can run it at regular intervals, reducing the risk of losing important files.
