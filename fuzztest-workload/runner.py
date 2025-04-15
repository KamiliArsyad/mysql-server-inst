import os
import polars as pl
import sys
import subprocess as sp
import random
import json
import time
from tqdm import tqdm
from datetime import datetime

random.seed(42)

# Check command-line arguments
if len(sys.argv) < 2:
    print("Usage: python3 runner.py config_path")
    exit(-1)

# Load configuration from the JSON file
config_file = sys.argv[1]
with open(config_file, 'r') as file:
    config = json.load(file)

# Extract parameters from configuration and command-line arguments
N = config['iteration']

# 'Binary' refers not only to the binary but also its configuration
PROG_BIN = config['prog-bin']
ELLE_BIN = config['elle-bin']
EDN_MAKER_BIN = config['edn-maker-bin']
WORKLOAD_BIN = config['workload-bin']
SHUTDOWN_CMD = config['shutdown-cmd']
CHECK_READY_CMD = config['check-ready-cmd']
# ELLE_BIN = '/home/arkamili/target/elle-cli-0.1.8-standalone.jar --model list-append'

def wait_for_server_ready(cmd, timeout=30):
    start = time.time()
    while time.time() - start < timeout:
        result = sp.run(cmd, shell=True, stdout=sp.DEVNULL, stderr=sp.DEVNULL)
        if result.returncode == 0:
            return True
        time.sleep(0.5)
    return False

# Base log directory (used for per-run logs and summary)
BASE_LOG_DIR = "/home/arkamili/mysql-inst/mysql-server/fuzztest-workload/logfiles"
os.makedirs(BASE_LOG_DIR, exist_ok=True)

# Summary file initialization
summary_file_path = os.path.join(BASE_LOG_DIR, "summary.txt")
start_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
iteration_logs = []
ok_count = 0
rt_count = 0
violation_count = 0

def update_summary(iteration, classification, seed):
    global ok_count, rt_count, violation_count, iteration_logs
    iteration_logs.append(f"Iteration {iteration}: {classification} (seed: {seed})")
    summary_header = f"Fuzzing run summary\nStarted at: {start_time}\nConfig: {json.dumps(config)}\n\n"
    summary_counts = (
        f"Iterations completed: {iteration + 1}\n"
        f"OK: {ok_count}\n"
        f"Realtime-only (RT): {rt_count}\n"
        f"Violations: {violation_count}\n\n"
    )
    summary_body = "\n".join(iteration_logs)
    with open(summary_file_path, 'w') as f:
        f.write(summary_header + summary_counts + summary_body)

# Main fuzzing loop
for i in tqdm(range(N), desc="Processing", unit="iterations"):
    # Create a directory for each run
    run_dir = os.path.join(BASE_LOG_DIR, f"run_{i}")
    run_seed = random.randint(0, 2**20)
    os.makedirs(run_dir, exist_ok=True)

    # Define log file name tagged with iteration number
    log_file = os.path.join(run_dir, f"out_raw_{i}.log")

    # Build the command with random seed and output file as environment variables
    command = f"RANDOM_SEED={run_seed} OUT_FILE={log_file} {PROG_BIN}"

    # Start the server in the background
    server_process = sp.Popen(command, shell=True, stdout=sp.DEVNULL, stderr=sp.DEVNULL)

    # Wait for the server to initialize (could replace with a loop to test connectivity)
    if not wait_for_server_ready(CHECK_READY_CMD, 15):
        print(f"Server did not become ready within timeout at iteration {i}")
        sp.run(SHUTDOWN_CMD, shell=True, stdout=sp.DEVNULL, stderr=sp.DEVNULL)
        server_process.wait()
        continue

    # Run the workload/client
    command = f"RANDOM_SEED={run_seed} {WORKLOAD_BIN} -L {run_dir}/workload_output_{i}"
    workload_result = sp.run(command, shell=True, stdout=sp.DEVNULL, stderr=sp.DEVNULL)
    if workload_result.returncode != 0:
        print(f"Workload failed at iteration {i} with exit code {workload_result.returncode}")
        # Shutdown the server if workload fails
        sp.run(SHUTDOWN_CMD, shell=True, stdout=sp.DEVNULL, stderr=sp.DEVNULL)
        server_process.wait()
        continue

    # Shutdown the server so that transactions complete
    shutdown_result = sp.run(SHUTDOWN_CMD, shell=True, stdout=sp.DEVNULL, stderr=sp.DEVNULL)
    if shutdown_result.returncode != 0:
        print(f"Shutdown command failed at iteration {i}")
        for i in range(6):
            shutdown_result = sp.run(SHUTDOWN_CMD, shell=True, stdout=sp.DEVNULL, stderr=sp.DEVNULL)
            print("retrying...")
            if shutdown_result.returncode == 0: break
            elif i == 5: exit();
            time.sleep(2 ** i)
    # Wait for the server process to exit
    server_process.wait()

    # Run the translator to generate the EDN file
    output_translated_path = os.path.join(run_dir, 'out_translated.edn')
    translator_cmd = f"{EDN_MAKER_BIN} {log_file} {output_translated_path}"
    with open(output_translated_path, 'w') as f:
        translator_result = sp.run(translator_cmd, shell=True, stdout=f, stderr=sp.PIPE)
    if translator_result.returncode != 0:
        print(f"Translator failed at iteration {i}")
        print(translator_result.stderr.decode('utf-8'))
        continue  # Skip to the next iteration

    # Prepare directory for verifier output and path for result file
    out_directory = os.path.join(run_dir, 'out_directory')
    os.makedirs(out_directory, exist_ok=True)
    result_out_path = os.path.join(run_dir, 'result.out')

    # Run the verifier (Elle) and capture its output
    elle_cmd = f"java -jar {ELLE_BIN} {output_translated_path} --directory {out_directory}"
    with open(result_out_path, 'w') as f:
        elle_result = sp.run(elle_cmd, shell=True, stdout=f)

    # Check verifier output for errors
    with open(result_out_path, 'r') as f:
        result_out_content = f.read()

    # Classify iteration:
    # If result output doesn't contain "false", it's OK.
    # If it does, check anomaly files in out_directory.
    if 'false' not in result_out_content:
        classification = "OK"
        ok_count += 1
    else:
        violation_files = [f for f in os.listdir(out_directory) if f.endswith(".txt")]
        non_rt_found = [v for v in violation_files if 'realtime' not in v.lower()]

        if non_rt_found:
            classification = "VIOLATION"
            violation_count += 1
            print(f"Violation detected at iteration {i}")
        else:
            classification = "RT"
            rt_count += 1

    # Update summary file after each iteration
    update_summary(i, classification, run_seed)
