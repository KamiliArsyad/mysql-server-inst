#!/bin/bash
if [ $# -eq 0 ]; then
    echo "Usage: $0 <parent_directory>"
    exit 1
fi

parent_dir="$1"
declare -A counts
total=0
empty_count=0

for run in "$parent_dir"/run_*; do
    # Check if run is a directory
    [ -d "$run" ] || continue

    out="$run/out_directory"
    # If out_directory doesn't exist, count as empty and move on.
    if [ ! -d "$out" ]; then
        empty_count=$(( empty_count + 1 ))
        continue
    fi

    eligible_found=0
    for dir in "$out"/*; do
        [ -d "$dir" ] || continue
        name=$(basename "$dir")
        if [[ "$name" == "sccs" || "$name" == *realtime* || "$name" == "incompatible-order" ]]; then
            continue
        fi
        eligible_found=1
        count=$(find "$dir" -type f | wc -l)
        total=$(( total + count ))
        counts["$name"]=$(( ${counts["$name"]:-0} + count ))
    done

    # If no eligible directories were found, count this out_directory as empty.
    if [ "$eligible_found" -eq 0 ]; then
        empty_count=$(( empty_count + 1 ))
    fi
done

for key in "${!counts[@]}"; do
    echo "$key = ${counts[$key]}"
done
echo "==== total = $total"
echo "Empty or nonexistent out_directories = $empty_count"
