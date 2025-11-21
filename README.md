# MyDBman Backup

A simple shell script to back up MySQL/MariaDB databases, both local and running in Docker containers.

Files:
- `mydbman.sh` — main script (bash)
- `mydbman.conf.sample` — sample configuration file to copy as `mydbman.conf`

## How to use

1. Clone the repository:

```bash
git clone https://github.com/laninisimone/MyDBman-Backup.git
cd MyDBman-Backup
```

2. Copy the sample file in the same folder as the script and edit it:

```bash
cp mydbman.conf.sample mydbman.conf
# Edit BASE_DIR and database sections as needed
```

3. Run the script (by default it reads `mydbman.conf` in the same path as the script):

```bash
bash mydbman.sh
# or specify an alternative config file
bash mydbman.sh -c /path/to/my_config.conf
```
**IMPORTANT**: The script requires bash, not sh. Always run it with:

## Config format

The file is INI-style with one section per database. It defines `BASE_DIR` and `[db_name]` sections with connection parameters:

```ini
BASE_DIR=/home/user/db_backups

[my_docker_db]
type=docker
host=my_db_container
user=my_db_user
password=my_db_password
separate=true
compress=true
engine=mysql

[local_mysql]
type=native
host=localhost
user=my_local_db_user
password=my_local_db_password
separate=true
compress=false
engine=mysql

[remote_mysql]
type=native
host=192.168.1.100
user=remote_user
password=remote_password
separate=false
compress=true
engine=mariadb
retention=5
```

### Per-section parameters:
- **type**: `docker` or `native`
- **host**: container name (for docker) or hostname/IP (for native)
- **user**: database username (default: `root` if omitted)
- **password**: database password (default: empty if omitted)
- **separate**: `true` for per-database dumps, `false` for full dump (`--all-databases`)
- **compress**: `true` for `.sql.gz`, `false` for `.sql`
- **engine**: `mysql` or `mariadb` (default: `mysql`)
 - **retention**: integer `>=0`; if set, keeps only the latest `retention+1` backups (per section or per database), deleting older ones

## Script behavior

- For each `[name]` section in the config:
	- if `separate=false`: runs `mysqldump --all-databases --single-transaction=TRUE` and saves to
		`BASE_DIR/name/YYYY_MM_DD_HHMMSS_complete_dump.sql[.gz]`
	- if `separate=true`: first runs `SHOW DATABASES`, then dumps each database (excluding system ones), saving to
		`BASE_DIR/name/<db_name>/YYYY_MM_DD_HHMMSS_<db_name>_dump.sql[.gz]`
- For `type=docker`: uses `docker exec -i <host> <dump_bin> ...` / `<db_client> ...`
- For `type=native`: calls `<dump_bin>` / `<db_client>` directly on the host system, where:
	- if `engine=mysql`: `<dump_bin>=mysqldump`, `<db_client>=mysql`
	- if `engine=mariadb`: `<dump_bin>=mariadb-dump`, `<db_client>=mariadb`
- If `compress=true` (default): compressed output `.sql.gz`, otherwise `.sql`

## Options

```bash
bash mydbman.sh [-c config_file] [-h]
```

- `-c FILE`: use an alternative config file
- `-h`: show help

## Assumptions and notes

- For native dumps: the binaries `mysqldump`/`mysql` or `mariadb-dump`/`mariadb` (depending on `engine`) must be available in `PATH`
- For Docker dumps: the container must have the same binaries available (`mysqldump`/`mysql` or `mariadb-dump`/`mariadb`)
- Credentials are passed directly to the commands (be careful with security)

## Quick syntax check (optional)

```bash
# check syntax (requires bash)
bash -n mydbman.sh
```

## Example run

```bash
# run backup with compression (default)
bash mydbman.sh

# use an alternative config
bash mydbman.sh -c /path/to/custom_config.conf

# after execution you'll find the files in BASE_DIR
```

## Common issues

- **"Illegal option -o pipefail"**: you are using `sh` instead of `bash`. Always use `bash mydbman.sh`
- "docker: command not found": install Docker or only use native backups
- "mysqldump: command not found": install the MySQL/MariaDB client tools
- "Access denied": check user/password in the config sections
- Container not found: ensure the container is running and the name is correct

## Cron automation example

To schedule automatic backups, add a cron job. Edit your crontab:

```bash
crontab -e
```

Example entries:

```cron
# Daily backup at 4:00 AM
0 4 * * * /bin/bash /path/to/MyDBman-Backup/mydbman.sh >> /var/log/mydbman-backup.log 2>&1

# Every 6 hours
0 */6 * * * /bin/bash /path/to/MyDBman-Backup/mydbman.sh

# Weekly on Sunday at 10:00 PM with custom config
0 22 * * 0 /bin/bash /path/to/MyDBman-Backup/mydbman.sh -c /path/to/custom.conf
```

**Important notes for cron:**
- Use absolute paths for both the script and config file
- Ensure the cron user has permissions to access Docker (if using Docker backups)
- Consider redirecting output to a log file for troubleshooting
- Test your cron command manually before scheduling it
