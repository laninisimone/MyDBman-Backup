# MyDBman Backup

Questo repository contiene uno script shell per eseguire backup di tutti i database MySQL/MariaDB sia locali che presenti in container Docker.

File creati:
- `mydbman.sh` — script principale (bash)
- `mydbman.conf.sample` — esempio di file di configurazione da copiare come `mydbman.conf`

## Come usare

**IMPORTANTE**: Lo script richiede bash, non sh. Eseguilo sempre con:

```bash
bash mydbman.sh
```

1. Copia il sample nella stessa cartella dello script e modificalo:

```bash
cp mydbman.conf.sample mydbman.conf
# Modifica BASE_DIR e le sezioni database come necessario
```

2. Esegui lo script (default legge `mydbman.conf` nello stesso percorso dello script):

```bash
bash mydbman.sh
# oppure specificare un file di config alternativo
bash mydbman.sh -c /percorso/a/mio_config.conf
```

## Formato del config

Il file è in formato INI con sezioni per ogni database. Definisce `BASE_DIR` e sezioni `[nome_db]` con i parametri di connessione:

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
```

### Parametri per sezione:
- **type**: `docker` o `native`
- **host**: nome del container (per docker) o hostname/IP (per native)
- **user**: username del database (default: `root` se omesso)
- **password**: password del database (default: vuota se omessa)
- **separate**: `true` per dump per singolo database, `false` per dump completo (`--all-databases`)
- **compress**: `true` per `.sql.gz`, `false` per `.sql`
- **engine**: `mysql` o `mariadb` (default: `mysql`)

## Comportamento dello script

- Per ogni sezione `[nome]` del config:
	- se `separate=false`: esegue `mysqldump --all-databases --single-transaction=TRUE` e salva in
		`BASE_DIR/nome/AAAA_MM_GG_HHMMSS_complete_dump.sql[.gz]`
	- se `separate=true`: prima fa `SHOW DATABASES` e poi esegue un dump per ogni database (esclusi sistemi), salvando in
		`BASE_DIR/nome/<db_name>/AAAA_MM_GG_HHMMSS_<db_name>_dump.sql[.gz]`
- Per `type=docker`: usa `docker exec -i <host> <dump_bin> ...` / `<db_client> ...`
- Per `type=native`: usa direttamente `<dump_bin>` / `<db_client>` sul sistema host, dove:
	- se `engine=mysql`: `<dump_bin>=mysqldump`, `<db_client>=mysql`
	- se `engine=mariadb`: `<dump_bin>=mariadb-dump`, `<db_client>=mariadb`
- Se `compress=true` (default): output compresso `.sql.gz`, altrimenti `.sql`

## Opzioni

```bash
bash mydbman.sh [-c config_file] [-h]
```

- `-c FILE`: usa file di config alternativo
- `-h`: mostra help

## Assunzioni e note

- Per dump nativi: i binari `mysqldump`/`mysql` o `mariadb-dump`/`mariadb` (a seconda di `engine`) devono essere nel PATH
- Per dump in docker: il container deve avere disponibili gli stessi binari (`mysqldump`/`mysql` o `mariadb-dump`/`mariadb`)
- Le credenziali sono passate direttamente ai comandi (attenzione alla sicurezza)

## Controllo rapido della sintassi (opzionale)

```bash
# check syntax (richiede bash disponibile)
bash -n mydbman.sh
```

## Esempio di run

```bash
# esegui il backup con compressione (default)
bash mydbman.sh

# usa config alternativo
bash mydbman.sh -c /path/to/custom_config.conf

# dopo l'esecuzione troverai i file in BASE_DIR
```

## Problemi comuni

- **"Illegal option -o pipefail"**: stai usando `sh` invece di `bash`. Usa sempre `bash mydbman.sh`
- "docker: command not found": installa Docker o esegui solo backup nativi
- "mysqldump: command not found": installa il client MySQL/MariaDB
- "Access denied": verifica user/password nelle sezioni del config
- Container non trovato: verifica che il container sia in esecuzione e il nome sia corretto
