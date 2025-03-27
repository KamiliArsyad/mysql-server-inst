import os
import polars as pl
import sys
import subprocess as sp
import random
import json
import time
from tqdm import tqdm

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
# ELLE_BIN = '/home/arkamili/target/elle-cli-0.1.8-standalone.jar --model list-append'

# Main fuzzing loop
for i in tqdm(range(N), desc="Processing", unit="iterations"):
    # Create a directory for each run
    log_dir = "/home/arkamili/mysql-inst/mysql-server/fuzztest-workload/logfiles"
    run_dir = os.path.join(log_dir, f"run_{i}")
    run_seed = random.randint(0, 2**20)
    os.makedirs(log_dir, exist_ok=True)
    os.makedirs(run_dir, exist_ok=True)

    # Define log file name tagged with iteration number
    log_file = os.path.join(run_dir, f"out_raw_{i}.log")

    # Build the command with random seed and output file as environment variables
    command = f"RANDOM_SEED={run_seed} OUT_FILE={log_file} {PROG_BIN}"

    # Start the server in the background
    server_process = sp.Popen(command, shell=True, stdout=sp.DEVNULL, stderr=sp.DEVNULL)

    # Wait for the server to initialize (could replace with a loop to test connectivity)
    time.sleep(5)  # Adjust this wait time as needed

    # Run the workload/client
    command = f"RANDOM_SEED={run_seed} {WORKLOAD_BIN}"
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
    if elle_result.returncode != 0:
        print(f"Verifier failed at iteration {i}")
        continue  # Skip to the next iteration

    # Check verifier output for errors
    with open(result_out_path, 'r') as f:
        result_out_content = f.read()
        continue;
        if 'false' in result_out_content:
            print(f"Error detected at iteration {i}")
            # Optionally log or take further action on errors
            continue