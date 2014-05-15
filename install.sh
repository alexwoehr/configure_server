#!/bin/bash

# USAGE:
#   $0 [SETUP_DIR]
# SETUP_DIR: All files are moved to this directory.

# Setup variables
source ./setup_vars.sh \
|| (echo "Cannot find setup_vars.sh. Exiting..." && exit 3)

if [[ -n "$1" ]]; then
  SETUP_DIR="$1"
else
  SETUP_DIR=`pwd`
fi

# Setup LIB_DIR if necessary
if [ "$SETUP_DIR" != "$LIB_DIR" ]; then
  echo "Moving contents to LIB_DIR ($LIB_DIR)..."
  mkdir --parents "$LIB_DIR"
  cp -rf "$SETUP_DIR"/* "$LIB_DIR"
fi

# Setup TMP_DIR
echo "Creating TMP_DIR ($TMP_DIR)..."
mkdir --parents "$TMP_DIR"

# Setup special user -- TODO

# Finally, let them know to change directories. We can't do that for them.
echo
echo "Please cd to LIB_DIR now to continue with setup:"
echo "cd $LIB_DIR"

