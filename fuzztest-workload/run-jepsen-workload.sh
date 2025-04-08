#!/usr/bin/env bash
# Simple reproduction of the workload transactions for MySQL

# Configuration
DB_USER="root"
DB_HOST="localhost"
DB_NAME="jepsen_test"
SOCKET_PATH="/home/arkamili/mysql-inst/mysql-server/cmake-build-debug/mysql/mysql.sock"
SOCKET_OPTION="--socket=${SOCKET_PATH}"
LOG_DIR=""

usage() {
  echo "Usage: $0 [-L <log_directory>]" 1>&2
  exit 1
}

# Parse command-line options
while getopts "L:h" opt; do
  case $opt in
    L) LOG_DIR="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

# Create log directory if specified
if [ -n "$LOG_DIR" ]; then
  mkdir -p "$LOG_DIR" || { echo "Cannot create log directory: $LOG_DIR"; exit 1; }
  echo "Logging enabled. Logs will be written to $LOG_DIR"
fi

# 1. Setup: create DB, table, and initial data
mysql -u "$DB_USER" -h "$DB_HOST" $SOCKET_OPTION -e "
DROP DATABASE IF EXISTS ${DB_NAME};
CREATE DATABASE ${DB_NAME};
USE ${DB_NAME};
SET GLOBAL TRANSACTION ISOLATION LEVEL REPEATABLE READ;
DROP TABLE IF EXISTS people;
CREATE TABLE people (
  id INT unsigned NOT NULL AUTO_INCREMENT,
  name TEXT NOT NULL,
  gender TEXT NOT NULL,
  PRIMARY KEY (id)
);
DELETE FROM people;
INSERT INTO people (name, gender) VALUES ('moss', 'enby');
INSERT INTO people (name, gender) VALUES ('moss', 'enby');
INSERT INTO people (name, gender) VALUES ('moss', 'enby');
INSERT INTO people (name, gender) VALUES ('moss', 'enby');
" || { echo "Database setup failed."; exit 1; }

id=$(mysql -u "$DB_USER" -h "$DB_HOST" $SOCKET_OPTION -D ${DB_NAME} -N -s -e "SELECT id FROM people LIMIT 1;")
echo "Initial row inserted with id: $id"

echo "Database '${DB_NAME}' created and initialized."

# 2. Define transaction sessions
# Session 1: Name Change Transaction
session1() {
  mysql -u "$DB_USER" -h "$DB_HOST" $SOCKET_OPTION "$DB_NAME" <<EOF
SET SESSION transaction_isolation='REPEATABLE-READ';
START TRANSACTION;
SELECT 't1 starting', NOW(), id, name FROM people WHERE id = ${id} FOR UPDATE;
UPDATE people SET name = 'leaf' WHERE id = ${id};
SELECT 't1 done', NOW();
COMMIT;
EOF
}

# Session 2: Read Transaction (two selects sandwiching an update)
session2() {
  mysql -u "$DB_USER" -h "$DB_HOST" $SOCKET_OPTION "$DB_NAME" <<EOF
SET SESSION transaction_isolation='REPEATABLE-READ';
START TRANSACTION;
SELECT 't2 starting', NOW();
SELECT 't2a', NOW(), id, name FROM people WHERE id = ${id};
UPDATE people SET gender = 'male' WHERE id = ${id};
SELECT 't2b', NOW(), id, name FROM people WHERE id = ${id};
UPDATE people SET gender = 'none' WHERE id = ${id};
COMMIT;
EOF
}

# Session 3: Delete Transaction
session3() {
  mysql -u "$DB_USER" -h "$DB_HOST" $SOCKET_OPTION "$DB_NAME" <<EOF
SET SESSION transaction_isolation='REPEATABLE-READ';
START TRANSACTION;
SELECT 't3 starting', NOW(), id, name, gender FROM people WHERE id = ${id} FOR UPDATE;
DELETE FROM people WHERE id = ${id};
SELECT 't3 done', NOW();
COMMIT;
EOF
}

# Session 4: Insert Transaction (inserts a new row)
session4() {
  mysql -u "$DB_USER" -h "$DB_HOST" $SOCKET_OPTION "$DB_NAME" <<EOF
SET SESSION transaction_isolation='REPEATABLE-READ';
START TRANSACTION;
INSERT INTO people (name, gender) VALUES ('moss', 'helicopter');
SELECT 't4 done', NOW();
COMMIT;
EOF
}

echo "Starting concurrent transactions..."

# 3. Launch sessions concurrently, logging if requested
if [ -n "$LOG_DIR" ]; then
  session1 > "$LOG_DIR/session1.log" 2>&1 &
  pid1=$!
  session2 > "$LOG_DIR/session2.log" 2>&1 &
  pid2=$!
  session3 > "$LOG_DIR/session3.log" 2>&1 &
  pid3=$!
  session4 > "$LOG_DIR/session4.log" 2>&1 &
  pid4=$!
else
  session1 &
  pid1=$!
  session2 &
  pid2=$!
  session3 &
  pid3=$!
  session4 &
  pid4=$!
fi

wait $pid1 $pid2 $pid3 $pid4
echo "Concurrent transactions complete. Check logs if enabled."
