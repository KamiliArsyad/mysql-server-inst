#!/usr/bin/env bash

##############################################################################
# Default Configuration
##############################################################################

# MySQL connection info
DB_USER="root"
DB_HOST="localhost"
SOCKET_PATH="/home/arkamili/mysql-inst/mysql-server/cmake-build-debug/mysql/mysql.sock"

# Workload scripts directory
WORKLOAD_DIR="/home/arkamili/mysql-inst/mysql-server/fuzztest-workload"

# Script filenames
INIT_SCRIPT="init.sql"
STRING_SCRIPT="string-test.sql"
INT_SCRIPT="int-test.sql"
LOCKING_SCRIPT="locking-test.sql"

# Default ratio for string : int : locking
RATIO_STR=3
RATIO_INT=2
RATIO_LOCK=5

# Default total concurrency
DEFAULT_CONCURRENCY=10

# Default limits
MAX_TIME=0
MAX_RUNS=0

# Random seed
RANDOM_SEED="${RANDOM_SEED:-12345}"

# Optional log directory (not set by default)
LOG_DIR=""

##############################################################################
# Usage function
##############################################################################
usage() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  -c <concurrency>   Total number of worker processes (default: $DEFAULT_CONCURRENCY)"
  echo "  -t <max_time_sec>  Maximum time (seconds) per worker (0 = unlimited)"
  echo "  -r <max_runs>      Maximum runs (iterations) per worker (0 = unlimited)"
  echo "  -L <log_directory> If set, logs each worker's queries/results to separate files"
  echo "  -h                 Show this help message"
  echo
  echo "Environment variable (optional):"
  echo "  RANDOM_SEED        Seed for all MySQL sessions (default: 12345)"
  exit 1
}

##############################################################################
# Parse command-line options
##############################################################################
CONCURRENCY=$DEFAULT_CONCURRENCY

while getopts ":c:t:r:L:h" opt; do
  case $opt in
    c) CONCURRENCY="$OPTARG" ;;
    t) MAX_TIME="$OPTARG" ;;
    r) MAX_RUNS="$OPTARG" ;;
    L) LOG_DIR="$OPTARG" ;;
    h) usage ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
    :)  echo "Option -$OPTARG requires an argument." >&2; usage ;;
  esac
done

# Validate numeric inputs
if ! [[ "$CONCURRENCY" =~ ^[0-9]+$ ]]; then
  echo "Error: concurrency (-c) must be a positive integer."
  exit 1
fi
if ! [[ "$MAX_TIME" =~ ^[0-9]+$ ]]; then
  echo "Error: max_time (-t) must be a non-negative integer."
  exit 1
fi
if ! [[ "$MAX_RUNS" =~ ^[0-9]+$ ]]; then
  echo "Error: max_runs (-r) must be a non-negative integer."
  exit 1
fi

##############################################################################
# Compute how many workers per script using 3:2:5 ratio
##############################################################################
RATIO_SUM=$((RATIO_STR + RATIO_INT + RATIO_LOCK))

STR_WORKERS=$(( CONCURRENCY * RATIO_STR / RATIO_SUM ))
INT_WORKERS=$(( CONCURRENCY * RATIO_INT / RATIO_SUM ))
LOCK_WORKERS=$(( CONCURRENCY * RATIO_LOCK / RATIO_SUM ))

ALLOCATED=$(( STR_WORKERS + INT_WORKERS + LOCK_WORKERS ))
LEFTOVER=$(( CONCURRENCY - ALLOCATED ))
if [ $LEFTOVER -gt 0 ]; then
  LOCK_WORKERS=$(( LOCK_WORKERS + LEFTOVER ))
fi

echo "--------------------------------------------------------"
echo "Concurrency: $CONCURRENCY total"
echo " -> $STR_WORKERS string-test workers"
echo " -> $INT_WORKERS int-test workers"
echo " -> $LOCK_WORKERS locking-test workers"
echo "Max time (seconds): $MAX_TIME"
echo "Max runs: $MAX_RUNS"
echo "Random seed: $RANDOM_SEED"
if [ -n "$LOG_DIR" ]; then
  echo "Logging to: $LOG_DIR"
else
  echo "Logging: disabled"
fi
echo "--------------------------------------------------------"

##############################################################################
# 1) Run init script once
##############################################################################
echo "Running init script: $WORKLOAD_DIR/$INIT_SCRIPT"
mysql -u "$DB_USER" --socket="$SOCKET_PATH" -h "$DB_HOST" \
  --init-command="SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE; SELECT RAND($RANDOM_SEED);" \
  < "$WORKLOAD_DIR/$INIT_SCRIPT"
echo "Init done."
echo

##############################################################################
# 2) Function to run a workload script with optional logging
##############################################################################
run_workload() {
  local workload_name="$1"
  local worker_id="$2"
  local script_path="$3"
  local max_time="$4"
  local max_runs="$5"

  local start_time
  start_time=$(date +%s)
  local run_count=0

  while true; do
    if [ "$max_time" -gt 0 ]; then
      local now
      now=$(date +%s)
      local elapsed=$(( now - start_time ))
      if [ $elapsed -ge "$max_time" ]; then
        break
      fi
    fi

    if [ "$max_runs" -gt 0 ] && [ "$run_count" -ge "$max_runs" ]; then
      break
    fi

    if [ -n "$LOG_DIR" ]; then
      # Append all query and result output to log file
      mkdir -p "$LOG_DIR"
      local log_file="$LOG_DIR/${workload_name}-worker-${worker_id}.log"
      mysql -u "$DB_USER" --socket="$SOCKET_PATH" -h "$DB_HOST" \
        --init-command="SELECT RAND($RANDOM_SEED);" \
        -v -v \
        < "$script_path" 2>&1 | tee -a "$log_file"
    else
      # No logging
      mysql -u "$DB_USER" --socket="$SOCKET_PATH" -h "$DB_HOST" \
        --init-command="SELECT RAND($RANDOM_SEED);" \
        < "$script_path"
    fi

    run_count=$(( run_count + 1 ))
  done
}

##############################################################################
# 3) Trap Ctrl-C to kill child processes
##############################################################################
trap 'echo "Stopping all workers..."; kill 0; exit 1' SIGINT SIGTERM

##############################################################################
# 4) Spawn workers
##############################################################################
# For each script type, spawn the required number of background workers
for i in $(seq 1 "$STR_WORKERS"); do
  run_workload "string" "$i" "$WORKLOAD_DIR/$STRING_SCRIPT" "$MAX_TIME" "$MAX_RUNS" &
done

for i in $(seq 1 "$INT_WORKERS"); do
  run_workload "int" "$i" "$WORKLOAD_DIR/$INT_SCRIPT" "$MAX_TIME" "$MAX_RUNS" &
done

for i in $(seq 1 "$LOCK_WORKERS"); do
  run_workload "locking" "$i" "$WORKLOAD_DIR/$LOCKING_SCRIPT" "$MAX_TIME" "$MAX_RUNS" &
done

##############################################################################
# 5) Wait for all background workers
##############################################################################
wait

echo
echo "All workers finished."
