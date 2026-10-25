# Project 3 (Experiment 9): File Backup Script

A Bash script that automatically backs up one directory to another using **rsync** (incremental snapshots) and **tar + bzip2** (compressed archives), scheduled with **cron**.

## 1. Objective

- Automate file backups from a source directory to a destination directory.
- Save disk space with incremental backups (unchanged files are hard-linked).
- Keep compressed full archives.
- Log every step and rotate old backups.
- Run everything automatically with cron.

## 2. Files

| File | Purpose |
|---|---|
| `backup_script.sh` | The backup script |
| `log/backup.log` | Created automatically on first run |
| `README.md` | This report |

## 3. Requirements and setup

```bash
sudo apt install rsync        # Debian/Ubuntu
chmod +x backup_script.sh
```

## 4. Usage

```bash
./backup_script.sh [-c] [-k N] <source_directory> <destination_directory>
```

| Option | Meaning |
|---|---|
| `-c` | Also create a compressed `.tar.bz2` archive of the backup |
| `-k N` | Keep only the newest N backups (default 5) |

Example:

```bash
mkdir -p ~/project_data ~/backups
echo "hello" > ~/project_data/a.txt
./backup_script.sh -c -k 5 ~/project_data ~/backups
```

Resulting layout:

```
~/backups/
├── backup_2026-10-25_18-00-00/     <- snapshot (full browsable copy)
├── backup_2026-10-25_19-00-00/
├── latest -> backup_2026-10-25_19-00-00
└── archives/
    └── backup_2026-10-25_19-00-00.tar.bz2
```

## 5. How the script works

1. **Parameter check:** `getopts` reads the options; `$#` must equal 2 after that, otherwise a usage message is shown and the script exits with `exit 1`.
2. **Validation:** source and destination must be existing directories, must differ, and the destination must not be inside the source (otherwise the backup would copy itself endlessly). It also checks that rsync is installed.
3. **Logging:** a `log()` function writes timestamped lines to `log/backup.log` (stored next to the script, so cron runs find it regardless of the working directory) and prints them on screen.
4. **Lock:** `flock` stops two backups from running at the same time.
5. **Incremental snapshot:** `rsync -a --delete --link-dest=<previous backup>` copies the source into a new timestamped folder.
   - Unchanged files become **hard links** to the previous backup (same inode, no extra space).
   - New or changed files are copied.
   - `--delete` removes files from the new snapshot if they were deleted in the source.
   - The copy goes to a `.partial` folder first and is renamed only on success, so a failed run never leaves a half-finished backup.
6. **`latest` symlink:** `ln -sfn` always points to the newest backup.
7. **Compression (`-c`):** `tar -cjf` creates `archives/backup_<timestamp>.tar.bz2`.
8. **Rotation:** if there are more than N backups (default 5), the oldest are deleted. Because of hard links, deleting an old snapshot never damages newer ones.

## 6. Scheduling with cron

Open the crontab:

```bash
crontab -e
```

Add (use full absolute paths; cron has a minimal environment):

```cron
# Every day at 5:30 PM - incremental snapshot, keep 7
30 17 * * *  /home/user/linux_backup_project/backup_script.sh -k 7 /home/user/project_data /home/user/backups/daily

# Every Friday at 6:00 PM - snapshot + compressed archive, keep 4
00 18 * * 5  /home/user/linux_backup_project/backup_script.sh -c -k 4 /home/user/project_data /home/user/backups/weekly

# 1st of every month at 6:00 AM - snapshot + compressed archive, keep 12
00 6 1 * *   /home/user/linux_backup_project/backup_script.sh -c -k 12 /home/user/project_data /home/user/backups/monthly
```

The destination folders must exist first: `mkdir -p ~/backups/{daily,weekly,monthly}`.

Cron field order: `minute hour day-of-month month day-of-week command`.

Check the schedule with `crontab -l`, and the results with `tail -f log/backup.log`.
(For a quick test, use `* * * * *` to run every minute, then change it back.)

## 7. Testing and verification

```bash
# Setup
mkdir -p ~/src ~/dst
echo a > ~/src/a.txt; echo b > ~/src/b.txt

# Run 1: full copy
./backup_script.sh ~/src ~/dst

# Change the source: add c.txt, delete b.txt
echo c > ~/src/c.txt; rm ~/src/b.txt
sleep 1
./backup_script.sh -c ~/src ~/dst

# Verify hard links: a.txt has the SAME inode number in both backups
ls -li ~/dst/backup_*/a.txt

# Verify the symlink and archive
ls -l ~/dst ~/dst/archives

# Verify rotation: run with -k 2 several times, only 2 backups remain
for i in 1 2 3; do sleep 1; ./backup_script.sh -k 2 ~/src ~/dst; done
ls ~/dst

# Verify error handling
./backup_script.sh                    # usage message
./backup_script.sh ~/src /nonexistent # directory error

# Restore a file from a compressed archive
mkdir ~/restore && tar -xjf ~/dst/archives/backup_*.tar.bz2 -C ~/restore
```

Take screenshots of these outputs for your submission.

## 8. Tools compared

| | rsync | tar + bzip2 |
|---|---|---|
| Type | Incremental sync | Full archive |
| Space use | Very low (hard links) | Smaller via compression, but a full copy each time |
| Speed | Fast (only changes) | Slower (reads everything) |
| Browse without extracting | Yes | No |
| Best for | Daily/frequent backups | Monthly, long-term storage |

## 9. Course outcome mapping

- **CO1:** Hard links, inodes, symlinks, exit codes, cron environment.
- **CO2:** Script and cron configuration, rsync and tar execution.
- **CO3:** Input validation, error handling, logs to diagnose failures, a lock for process control.
- **CO4:** Performance (incremental vs. full) and safety (`--delete` precautions, partial-copy protection, destination-inside-source check).
- **CO5:** A rotation policy with daily, weekly and monthly strategies.

## 10. Possible viva questions

- **Why `#!/bin/bash`?** It tells the system which interpreter runs the script.
- **What does `$#` mean?** The number of arguments passed.
- **What does `rsync -a` do?** Archive mode: recursive, and preserves permissions, timestamps, symlinks and ownership.
- **What does `--link-dest` do?** It hard-links unchanged files to the previous backup instead of copying them.
- **What is the danger of `--delete`?** If source and destination are swapped, you can wipe your data. The script checks both paths first.
- **Why use full paths in cron?** Cron runs with a minimal `PATH` and a different working directory.
- **Hard link vs. symlink?** A hard link is another name for the same inode (data survives if the original name is deleted). A symlink is a pointer to a path and breaks if the target is removed.

## 11. Limitations / future improvements

- Destination paths containing spaces are not supported in the rotation step.
- Email alerts on failure.
- Backing up to a remote server over SSH (`rsync -e ssh`).
- Exclude patterns (`--exclude`).
