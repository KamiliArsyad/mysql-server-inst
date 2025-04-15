#!/usr/bin/env bash
# Simple reproduction of the non-repeatable read bug in REPEATABLE-READ isolation

# Configuration
DB_USER="root"
DB_HOST="localhost"
DB_NAME="test_bug"
SOCKET_PATH="/home/arkamili/mysql-inst/mysql-server/cmake-build-debug/mysql/mysql.sock"
SOCKET_OPTION="--socket=${SOCKET_PATH}"
LOG_DIR=""

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
CREATE TABLE some_table (
  id BIGINT,
  col VARCHAR(10),
  PRIMARY KEY (id),
  UNIQUE INDEX (col)
);
INSERT INTO some_table(id, col) VALUES (3, NULL), (4, '5');
" || { echo "Database setup failed."; exit 1; }

echo "Database '${DB_NAME}' created and initialized."

# 2. Define transaction sessions

# Session 1: Locks rows, waits, deletes/inserts then commits.
session1() {
  mysql -u "$DB_USER" -h "$DB_HOST" $SOCKET_OPTION "$DB_NAME" <<'EOF'
SET SESSION transaction_isolation='REPEATABLE-READ';
START TRANSACTION;
SELECT 't1', NOW(), id, col FROM some_table WHERE col IN (5) OR id IN (3) FOR UPDATE;
DELETE FROM some_table WHERE col IN (5) OR id IN (3);
INSERT INTO some_table(id, col) VALUES (3, 5);
SELECT 't1 done', NOW();
COMMIT;
EOF
}

# Session 2: Starts after 1 sec, runs two SELECT ... FOR UPDATE queries.
session2() {
  mysql -u "$DB_USER" -h "$DB_HOST" $SOCKET_OPTION "$DB_NAME" <<'EOF'
SET SESSION transaction_isolation='REPEATABLE-READ';
START TRANSACTION;
SELECT 't2 starting', NOW();
SELECT 't2a', NOW(), id, col FROM some_table WHERE col IN (('5')) FOR UPDATE;
SELECT 't2b', NOW(), id, col FROM some_table WHERE col IN (('5')) FOR UPDATE;
COMMIT;
EOF
}

echo "Starting concurrent transactions..."

# 3. Launch sessions concurrently, logging if requested
echo "Starting concurrent transactions..."
if [ -n "$LOG_DIR" ]; then
  session1 > "$LOG_DIR/session1.log" 2>&1 &
  pid1=$!
  session2 > "$LOG_DIR/session2.log" 2>&1 &
  pid2=$!
else
  session1 &
  pid1=$!
  session2 &
  pid2=$!
fi

wait $pid1 $pid2
echo "Concurrent transactions complete. Check logs if enabled."