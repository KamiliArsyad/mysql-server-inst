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

# Default total concurrency (sum of workers)
DEFAULT_CONCURRENCY=10

# Default limits (0 means "unlimited")
MAX_TIME=0   # in seconds
MAX_RUNS=0   # per worker

##############################################################################
# Usage function
##############################################################################
usage() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  -c <concurrency>   Total number of worker processes (default: $DEFAULT_CONCURRENCY)"
  echo "  -t <max_time_sec>  Maximum time (seconds) each worker runs (default: unlimited)"
  echo "  -r <max_runs>      Maximum number of runs (iterations) per worker (default: unlimited)"
  echo "  -h                 Show this help message"
  echo
  echo "Example:"
  echo "  $0 -c 10 -t 60 -r 100"
  echo "  (Runs 10 workers total, each will stop after 60 seconds or 100 runs, whichever is first.)"
  exit 1
}

##############################################################################
# Parse command-line options
##############################################################################
CONCURRENCY=$DEFAULT_CONCURRENCY

while getopts ":c:t:r:h" opt; do
  case $opt in
    c)
      CONCURRENCY="$OPTARG"
      ;;
    t)
      MAX_TIME="$OPTARG"
      ;;
    r)
      MAX_RUNS="$OPTARG"
      ;;
    h)
      usage
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      usage
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      usage
      ;;
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
# Sum of ratio
RATIO_SUM=$((RATIO_STR + RATIO_INT + RATIO_LOCK))

# Basic integer division for each
STR_WORKERS=$(( CONCURRENCY * RATIO_STR / RATIO_SUM ))
INT_WORKERS=$(( CONCURRENCY * RATIO_INT / RATIO_SUM ))
LOCK_WORKERS=$(( CONCURRENCY * RATIO_LOCK / RATIO_SUM ))

# Because of integer division, we may miss a few workers if there's rounding.
# Optional: distribute leftover workers to some group
ALLOCATED=$(( STR_WORKERS + INT_WORKERS + LOCK_WORKERS ))
LEFTOVER=$(( CONCURRENCY - ALLOCATED ))
if [ $LEFTOVER -gt 0 ]; then
  # Just add leftover to locking-test (arbitrary choice) or distribute as needed
  LOCK_WORKERS=$(( LOCK_WORKERS + LEFTOVER ))
fi

echo "--------------------------------------------------------"
echo "Concurrency: $CONCURRENCY total"
echo " -> $STR_WORKERS string-test workers"
echo " -> $INT_WORKERS int-test workers"
echo " -> $LOCK_WORKERS locking-test workers"
echo "Max time (seconds): $MAX_TIME (0 = unlimited)"
echo "Max runs: $MAX_RUNS (0 = unlimited)"
echo "--------------------------------------------------------"

##############################################################################
# 1) Run init script once (blocking)
##############################################################################
echo "Running init script: $WORKLOAD_DIR/$INIT_SCRIPT"
mysql -u "$DB_USER" --socket="$SOCKET_PATH" -h "$DB_HOST" < "$WORKLOAD_DIR/$INIT_SCRIPT"
echo "Init done."
echo

##############################################################################
# 2) Function to run a workload script with time/runs bounding
##############################################################################
run_workload() {
  local script_path="$1"
  local max_time="$2"
  local max_runs="$3"

  # Record the start time (epoch seconds)
  local start_time=$(date +%s)
  local run_count=0

  while true; do
    # Check time bound
    if [ "$max_time" -gt 0 ]; then
      local now=$(date +%s)
      local elapsed=$(( now - start_time ))
      if [ $elapsed -ge "$max_time" ]; then
        break
      fi
    fi

    # Check runs bound
    if [ "$max_runs" -gt 0 ] && [ "$run_count" -ge "$max_runs" ]; then
      break
    fi

    # Run the SQL file
    mysql -u "$DB_USER" --socket="$SOCKET_PATH" -h "$DB_HOST" < "$script_path"

    # Increment run count
    run_count=$(( run_count + 1 ))
  done

  # End of worker
}

##############################################################################
# 3) Trap Ctrl-C so we can kill child processes
##############################################################################
trap 'echo "Stopping all workers..."; kill 0; exit 1' SIGINT SIGTERM

##############################################################################
# 4) Spawn workers
##############################################################################
# Spawn string-test workers
for i in $(seq 1 "$STR_WORKERS"); do
  run_workload "$WORKLOAD_DIR/$STRING_SCRIPT" "$MAX_TIME" "$MAX_RUNS" &
done

# Spawn int-test workers
for i in $(seq 1 "$INT_WORKERS"); do
  run_workload "$WORKLOAD_DIR/$INT_SCRIPT" "$MAX_TIME" "$MAX_RUNS" &
done

# Spawn locking-test workers
for i in $(seq 1 "$LOCK_WORKERS"); do
  run_workload "$WORKLOAD_DIR/$LOCKING_SCRIPT" "$MAX_TIME" "$MAX_RUNS" &
done

##############################################################################
# 5) Wait for all background workers
##############################################################################
wait

echo
echo "All workers finished."
