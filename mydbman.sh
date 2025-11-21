#!/usr/bin/env bash
# MyDBman Backup
# Backup MySQL/MariaDB databases from local host or from docker containers.
# Reads configuration from an INI-style config file (default: same dir mydbman.conf).

# Check if running with bash
if [ -z "${BASH_VERSION:-}" ]; then
  echo "ERROR: This script requires bash. Please run with: bash $0" >&2
  exit 1
fi

set -euo pipefail

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONF_FILE="$SELF_DIR/mydbman.conf"

usage() {
  cat <<-USG
Usage: $0 [-c config_file] [-h]

Options:
  -c FILE   Use alternate config file (default: $CONF_FILE)
  -h        Show this help

Config file format (INI-style). Example in mydbman.conf.sample:
  BASE_DIR=/path/to/backups
  
  [nome_assegnato]
  type=docker|native
  host=...
  user=...
  password=...
  engine=mysql|mariadb   # if omitted: mysql
  separate=true|false
  compress=true|false   # if omitted: true

Notes:
  - type: docker|native
  - For docker: host = container name
  - For native: host = hostname/IP (default localhost)
  - If separate=false: full dump (--all-databases)
  - If separate=true: per-database dumps
  - If compress=true (default): .sql.gz, else .sql
USG
}

while getopts ":c:h" opt; do
  case $opt in
    c) CONF_FILE="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

if [ ! -f "$CONF_FILE" ]; then
  echo "Config file not found: $CONF_FILE" >&2
  echo "Create one based on mydbman.conf.sample in the same folder." >&2
  exit 2
fi

# Parse INI file
declare -A config
current_section=""

parse_ini() {
  while IFS= read -r line; do
    # Trim spazi
    line=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

    # Salta vuote o commenti
    case "$line" in
      ''|'#'*|';'*) continue ;;
    esac

    # Sezione [name]
    if echo "$line" | grep -Eq '^\[[^]]+\]$'; then
      current_section=$(echo "$line" | sed 's/^\[\(.*\)\]$/\1/')
      continue
    fi

    # Coppie key=value
    if echo "$line" | grep -Eq '^[^=]+=.*$'; then
      key=${line%%=*}
      value=${line#*=}
      # Rimuovi eventuali doppi apici
      value=$(echo "$value" | sed 's/^"//;s/"$//')

      if [ -n "$current_section" ]; then
        config["${current_section}.${key}"]="$value"
      else
        config["$key"]="$value"
      fi
    fi
  done < "$CONF_FILE"
}

parse_ini

BASE_DIR="${config[BASE_DIR]:-$SELF_DIR/backups}"
# Remove trailing slashes to avoid double '/'
BASE_DIR="${BASE_DIR%/}"
mkdir -p "$BASE_DIR"

timestamp() {
  date +%Y_%m_%d_%H%M%S
}

build_auth_args() {
  local type="$1" host="$2" user="$3" password="$4"
  local args=""

  if [[ -n "$user" ]]; then
    args+=" -u\"$user\""
  fi
  if [[ -n "$password" ]]; then
    args+=" -p\"$password\""
  fi
  if [[ "$type" != "docker" && -n "$host" && "$host" != "localhost" ]]; then
    args+=" -h\"$host\""
  fi
  echo "$args"
}

run_in_context() {
  local type="$1" host="$2" cmd="$3"
  if [[ "$type" == "docker" ]]; then
    docker exec -i "$host" sh -c "$cmd"
  else
    eval "$cmd"
  fi
}

run_dump_section() {
  local section="$1"

  local type="${config[$section.type]:-}"
  local host="${config[$section.host]:-localhost}"
  local user="${config[$section.user]:-root}"
  local password="${config[$section.password]:-}"
  local engine="${config[$section.engine]:-mysql}"
  local separate="${config[$section.separate]:-false}"
  local compress="${config[$section.compress]:-true}"

  if [[ -z "$type" ]]; then
    echo "ERROR: missing 'type' for section [$section]" >&2
    return 1
  fi
  if [[ "$type" != "docker" && "$type" != "native" ]]; then
    echo "ERROR: unknown type '$type' for section [$section]" >&2
    return 1
  fi
  if [[ "$engine" != "mysql" && "$engine" != "mariadb" ]]; then
    echo "ERROR: unknown engine '$engine' for section [$section] (use mysql|mariadb)" >&2
    return 1
  fi
  if [[ "$type" == "docker" && -z "$host" ]]; then
    echo "ERROR: host (container name) required for docker section [$section]" >&2
    return 1
  fi

  local ts dir_section
  ts=$(timestamp)
  dir_section="$BASE_DIR/$section"
  mkdir -p "$dir_section"

  local auth_args
  auth_args=$(build_auth_args "$type" "$host" "$user" "$password")

  echo "[*] Processing section [$section] type=$type engine=$engine host=$host separate=$separate compress=$compress"

  local dump_bin db_client
  if [[ "$engine" == "mysql" ]]; then
    dump_bin="mysqldump"
    db_client="mysql"
  else
    dump_bin="mariadb-dump"
    db_client="mariadb"
  fi

  if [[ "$type" == "native" ]]; then
    if ! command -v "$dump_bin" >/dev/null 2>&1; then
      echo "ERROR: $dump_bin not found for section [$section]" >&2
      return 1
    fi
    if ! command -v "$db_client" >/dev/null 2>&1; then
      echo "ERROR: $db_client client not found for section [$section]" >&2
      return 1
    fi
  fi

  if [[ "$separate" != "true" ]]; then
    local outfile_ext="sql"
    [[ "$compress" == "true" ]] && outfile_ext="sql.gz"
    local outfile="$dir_section/${ts}_complete_dump.$outfile_ext"
    local cmd="$dump_bin$auth_args --single-transaction=TRUE --all-databases"
    echo "    -> full dump -> $outfile"
    if [[ "$compress" == "true" ]]; then
      if run_in_context "$type" "$host" "$cmd" | gzip -c > "$outfile"; then
        echo "    OK  [$section] complete dump (compressed)"
      else
        echo "    FAIL [$section] complete dump" >&2
        rm -f "$outfile" || true
        return 1
      fi
    else
      if run_in_context "$type" "$host" "$cmd" > "$outfile"; then
        echo "    OK  [$section] complete dump"
      else
        echo "    FAIL [$section] complete dump" >&2
        rm -f "$outfile" || true
        return 1
      fi
    fi
  else
    echo "    -> fetching database list for [$section] ..."
    local list_cmd="$db_client$auth_args -N -e 'SHOW DATABASES;'"
    mapfile -t dbs < <(run_in_context "$type" "$host" "$list_cmd" | grep -vE '^(information_schema|performance_schema|mysql|sys)$' || true)

    if [[ "${#dbs[@]}" -eq 0 ]]; then
      echo "    WARN [$section] no databases found to dump"
      return 0
    fi

    for db in "${dbs[@]}"; do
      local db_dir="$dir_section/$db"
      mkdir -p "$db_dir"
      local outfile_ext="sql"
      [[ "$compress" == "true" ]] && outfile_ext="sql.gz"
      local outfile="$db_dir/${ts}_${db}_dump.$outfile_ext"
      local cmd="$dump_bin$auth_args --single-transaction=TRUE \"$db\""
      echo "    -> dumping db '$db' -> $outfile"
      if [[ "$compress" == "true" ]]; then
        if run_in_context "$type" "$host" "$cmd" | gzip -c > "$outfile"; then
          echo "       OK  db=$db (compressed)"
        else
          echo "       FAIL db=$db" >&2
          rm -f "$outfile" || true
        fi
      else
        if run_in_context "$type" "$host" "$cmd" > "$outfile"; then
          echo "       OK  db=$db"
        else
          echo "       FAIL db=$db" >&2
          rm -f "$outfile" || true
        fi
      fi
    done
  fi
}

# Find all sections (keys that contain a dot)
sections=()
for key in "${!config[@]}"; do
  if [[ "$key" =~ ^([^.]+)\. ]]; then
    section="${BASH_REMATCH[1]}"
    if [[ ! " ${sections[@]} " =~ " ${section} " ]]; then
      sections+=("$section")
    fi
  fi
done

if [[ ${#sections[@]} -eq 0 ]]; then
  echo "No database sections found in config. Nothing to do." >&2
  exit 0
fi

failed=0
for section in "${sections[@]}"; do
  if ! run_dump_section "$section"; then
    failed=$((failed+1))
  fi
done

if [[ "$failed" -gt 0 ]]; then
  echo "Completed with $failed failures." >&2
  exit 3
fi

echo "All backups finished successfully. Files in: $BASE_DIR"