#!/bin/sh

# Usage: install_a_script.sh "script_name" [LINK_DIR]
# script_name: Filename of the script, assumed to be in $SCRIPT_DIR
# LINK_DIR: Directory to link this script into. Assumed: /sbin

script="$1"

##########################
# Setup Variables
##########################
source ./setup_vars.sh \
|| (echo "Cannot find setup_vars.sh. Exiting..." && exit 3)

echo 
echo "=============================="
echo "== Installing Script $script"
echo "=============================="
echo

if [[ -n $2 ]]; then
  LINK_DIR="$2"
else
  LINK_DIR=/sbin
fi

echo "- Step 1: Ensure it is in scripts dir ($SCRIPTS_DIR)"
# Does it exist in script dir ye?
if [[ ! -e $SCRIPTS_DIR/$script ]]; then
  echo "... Does not exist in scripts dir yet ..."
  # Does it exist in our scripts subdirectory?
  if [[ ! -e $LIB_DIR/scripts/$script ]]; then
    echo "... FATAL ERROR: script not found."
    exit 3
  else
    echo "... Moving to $SCRIPTS_DIR ..."
    cp $LIB_DIR/scripts/$script $SCRIPTS_DIR/$script \
    && echo "...Done" \
    || (echo "...ERROR: could not copy to $SCRIPTS_DIR" && exit 1)
  fi
fi

echo "- Step 2: Link the script from $LINK_DIR"
if [[ -L $LINK_DIR/$script ]]; then
  echo "... Link already exists. Nothing to do."
else
  echo "... Linking to $LINK_DIR ..."
  ln --symbolic $SCRIPTS_DIR/$script $LINK_DIR/$script \
  && echo "...Done" \
  || (echo "...ERROR: could not link" && exit 1)
fi
echo "Done installing $script"

exit 0

