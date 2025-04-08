#!/usr/bin/env bash

# Defaults
NUM_RUNS=1
LOG_BASE_DIR="bug_exec"
SCRIPT_TO_RUN="./run-known-bug-test.sh"

# Parse options
while getopts "N:" opt; do
  case $opt in
    N) NUM_RUNS="$OPTARG" ;;
    *) echo "Usage: $0 -N <num_runs>"; exit 1 ;;
  esac
done

# Validate number of runs
if ! [[ "$NUM_RUNS" =~ ^[0-9]+$ ]]; then
  echo "Invalid number of runs: $NUM_RUNS"
  exit 1
fi

# Ensure log dir
mkdir -p "$LOG_BASE_DIR"

total_with_2a=0

for ((i = 1; i <= NUM_RUNS; i++)); do
  run_dir="${LOG_BASE_DIR}/run_$i"
  mkdir -p "$run_dir"

  echo "== Run $i =="

  start_time=$(date +%s%N)

  "$SCRIPT_TO_RUN" -L "$run_dir" > "${run_dir}/main.log" 2>&1

  end_time=$(date +%s%N)
  elapsed_ns=$((end_time - start_time))
  total_time_ns=$((total_time_ns + elapsed_ns))
  elapsed_ms=$((elapsed_ns / 1000000))

  if grep -q "2a" "${run_dir}/session2.log"; then
    ((total_with_2a++))
    echo "Run $i: '2a' found. Time: ${elapsed_ms} ms"
  else
    echo "Run $i: '2a' NOT found. Time: ${elapsed_ms} ms"
  fi
done

# Summary
avg_time_ms=$((total_time_ns / NUM_RUNS / 1000000))
echo "==========="
echo "Total runs        : $NUM_RUNS"
echo "Runs with '2a'    : $total_with_2a"
echo "Runs without it   : $((NUM_RUNS - total_with_2a))"
echo "Avg run time (ms) : $avg_time_ms"
echo "Total time (ms)   : $((total_time_ns / 1000000))"
