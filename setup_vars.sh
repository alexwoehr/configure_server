#!/bin/bash

# Setup Variables for setup scripts.
# This is an include, so we basically run silent.
# 
# Usage: setup_vars.sh [SCRIPT_PREFIX] [TMP_DIR_SUFFIX]
# - SCRIPT_PREFIX: helps us differentiate from other files, if you batch multiple scripts together in the same process
# - TMP_DIR_SUFFIX: lets you assign a human-readable description of the current run, that precedes $$ (process id)
#
# Paths and Files
# 
# Set Script Prefix
# Obtain from command line if possible

# Process SCRIPT_PREFIX from the invocation file name
export MAIN_SCRIPT_PREFIX=${0##*/}
export MAIN_SCRIPT_PREFIX=${SCRIPT_PREFIX%.*}
# Clean up any dangerous parts
export MAIN_SCRIPT_PREFIX=${SCRIPT_PREFIX/ \t\n//}

if [[ -n $1 ]]; then
  # Use $1
  export SCRIPT_PREFIX="$1"
else
  export SCRIPT_PREFIX=$MAIN_SCRIPT_PREFIX
fi

# Generate Directories
# TMP_DIR: Temporary directory, stores logs and tmp files from this run
# - Generally follows format: <pid>.<script name>.<user comment>
export TMP_DIR="/var/run/setup_script/$$.$MAIN_SCRIPT_PREFIX"
if [[ -n $2 ]]; then
  export TMP_DIR_SUFFIX="$2"
  export TMP_DIR="$TMP_DIR.$TMP_DIR_SUFFIX"
fi
mkdir --parents "$TMP_DIR"

# LIB_DIR: Probably current directory. Stores our data that doesn't change from run to run.
export LIB_DIR="/var/lib/setup_script"

# DATA_DIR: Contains data that drives different tasks
export DATA_DIR="$LIB_DIR/data"

# SCRIPTS_DIR: all scripts are in here
export SCRIPTS_DIR="$LIB_DIR/scripts"
mkdir --parents $SCRIPTS_DIR

# SCRATCH: The main scratch file used to save intermediate output
export SCRATCH="$TMP_DIR/$SCRIPT_PREFIX.tmp"

# Statistics and logs
export ACTIONS_COUNTER=0
export ACTIONS_TAKEN_FILE="$TMP_DIR/$SCRIPT_PREFIX.actions_taken.txt"

# Setup undo file to revert changes if necessary
export UNDO_FILE="$TMP_DIR/$SCRIPT_PREFIX.undo.sh"

# List of current partitions
# TODO: fix possible issue with /dev/xvd being too narrow
export PARTITIONS=`df --human-readable | grep ^/dev/xvd | awk '{print $NF}' | tr "\n" " "`


