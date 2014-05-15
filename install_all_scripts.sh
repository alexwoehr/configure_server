#!/bin/sh

# USAGE:
#   $0 [LINK_DIR]
# LINK_DIR: Assumed to be /sbin, as these are server administration scripts

if [[ -n $1 ]]; then
  LINK_DIR="$1"
else
  LINK_DIR=/sbin
fi

##########################
# Setup Variables
##########################
source ./setup_vars.sh \
|| (echo "Cannot find setup_vars.sh. Exiting..." && exit 3)

ls $LIB_DIR/scripts | tee $SCRATCH
for script in `cat $SCRATCH`; do
  echo "... Installing $script..."
  ./install_a_script.sh $script $LINK_DIR | sed "s/.*/[install_a_script] \0/" \
  && echo "... Installed $script into $LINK_DIR" \
  || (echo "... ERROR: Could not install $script into $LINK_DIR" && exit 3)
done

