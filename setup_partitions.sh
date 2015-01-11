#!/bin/sh

clear

echo 
echo "=============================="
echo "== WELCOME TO PARTITION SETUP SCRIPT"
echo "=============================="
echo

##########################
# Notes
##########################
# Exit statuses:
# - 0: Successful
# - 1: Serious error
# - 2: Amusing error
# - 3: Path not found
# - 99: Aborted at user's request
# - 255: test abort

##################
#
# Setup variables
# 
##################
# have to do this, since we are after the variables!
source ./setup_vars.sh \
|| (echo "Cannot find setup_vars.sh. Exiting..." && exit 3)

# Ensure directories exist
mkdir --parents "$TMP_DIR"

# Create files
> "$ACTIONS_TAKEN_FILE"

>  "$UNDO_FILE" echo "#!/bin/sh"
>> "$UNDO_FILE" echo            
chmod +x "$UNDO_FILE"

echo "------------------------------"
echo "-- Setup Global Variables"
echo "------------------------------"
echo "- Identifying partitions to use:"
echo "Good morning, here's what fdisk has to say:"
echo "-- press any key to continue --"
read proceed
fdisk -l | sed 's/.*/[fdisk says] \0/'
echo "Enter the device to substitute, or hit enter if bracketed default is okay."
echo
echo "* BEGIN PARTITION ENTRY *"
echo "* Enter the primary root device? [xvda1]"
echo -n "> "; read DEVICE_ROOT1
# Permit using standard "yes |" approach
if [ "$DEVICE_ROOT1" == "y" ]; then
  DEVICE_ROOT1="" # use default
fi
DEVICE_ROOT1=${DEVICE_ROOT1:-xvda1}
echo "* OK, you said:"
echo "*" `echo -n $DEVICE_ROOT1 | cat -A`
echo "*"
echo "* Enter the secondary root device? [xvdb]"
echo -n "> ";read DEVICE_ROOT2
if [ "$DEVICE_ROOT2" == "y" ]; then
  DEVICE_ROOT2="" # use default
fi
DEVICE_ROOT2=${DEVICE_ROOT2:-xvdb}
echo "* OK, you said:"
echo "*" `echo -n $DEVICE_ROOT2 | cat -A`
echo "*"
echo "* Enter the primary data device? [xvde]"
echo -n "> ";read DEVICE_DATA1
if [ "$DEVICE_DATA1" == "y" ]; then
  DEVICE_DATA1="" # use default
fi
DEVICE_DATA1=${DEVICE_DATA1:-xvde}
echo "* OK, you said:"
echo "*" `echo -n $DEVICE_DATA1 | cat -A`
echo "*"
echo "* END OF PARTITION ENTRY *"
echo "-- press any key to continue --"
read proceed
echo
echo "------------------------------"
echo "-- Runtime Global Variables"
echo "------------------------------"
echo "- (see setup_vars.sh for definition)"
echo PARTITIONS "${PARTITIONS:-(empty)}"
echo UNDO_FILE "$UNDO_FILE"
echo TMP_DIR "$TMP_DIR"
echo LIB_DIR "$LIB_DIR"
echo SCRATCH "$SCRATCH"
echo ACTIONS_COUNTER "$ACTIONS_COUNTER"
echo ACTIONS_TAKEN_FILE "$ACTIONS_TAKEN_FILE"
echo DEVICE_ROOT1 "$DEVICE_ROOT1"
echo DEVICE_ROOT2 "$DEVICE_ROOT2"
echo DEVICE_DATA1 "$DEVICE_DATA1"
echo "-- press any key to continue --"
read proceed

##################
#
# Partitions
# 
##################
echo 
echo "------------------------------"
echo "-- Install Parted"
echo "------------------------------"
echo "- (checking if it is installed yet)"
modflag="configure_server partitioning; install parted"
yum list installed \
| awk '{print $1}' \
| grep ^parted\\. \
  > $SCRATCH
if [ ! -s "$SCRATCH" ] ; then
  echo "Install parted? [y/N]"
  read proceed
  if [ "y" == "$proceed" ] ; then
    echo "Installing..."

    ( yum --assumeyes install parted \
      | sed 's/.*/[yum says] \0/') \
    || (echo "Could not install parted." && exit 1)

    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag

    # Append to undo file
    >> $UNDO_FILE echo "echo 'Removing parted...' "
    >> $UNDO_FILE echo "yum --assumeyes remove parted"
    echo "Wrote to undo file."
    echo "-- press any key to continue --"
    read proceed
  else
    echo "OK, no changes made."
  fi
else
  echo "No changes necessary. Looks like parted is already installed."
fi

echo 
echo "------------------------------"
echo "-- Run Partitioning Commands"
echo "------------------------------"
yum list installed \
| awk '{print $1}' \
| grep ^parted\\. \
  > $SCRATCH
if [ -s "$SCRATCH" ] && which "parted" ; then
  echo "parted command has been detected."
  echo "Proceed to interactive parted session? [y/N]"
  read proceed
  if [ "y" == "$proceed" ]; then
    echo "NOTE: Undo capability is EXTREMELY limited. Press ^Z at any time to fix your mess."
    echo
    echo "* BEGIN INTERACTIVE COMMAND QUEUEING *"
    # Read cmds into $SCRATCH, replacing spaces with ~~ so that the for works right
    cat $DATA_DIR/partition_cmds.txt \
    | grep --invert-match "^#" \
    | tr " \t" "~~" \
      > "$SCRATCH"
    for cmd in `cat $SCRATCH`; do
      # Get spaces into the string again
      cmd=`echo $cmd | tr "~" " "`
      # Replace device names
      cmd=${cmd//_DEVICE_ROOT1_/$DEVICE_ROOT1}
      cmd=${cmd//_DEVICE_ROOT2_/$DEVICE_ROOT2}
      cmd=${cmd//_DEVICE_DATA1_/$DEVICE_DATA1}
      echo "* Queue command below? [y/N]"
      echo "* $cmd"
      read proceed
      if [ "y" == "$proceed" ]; then
        # Important: quit when we're done, so it doesn't hang. Also, final newline after quit is important!!
        >> "$SCRATCH"1 echo $cmd
        echo "* Action queued."
      else
        echo "* OK, command was ignored."
      fi
    done
    >> "$SCRATCH"1 echo "quit"
    echo "* Full commands list below:"
    cat -A "$SCRATCH"1 | sed 's/.*/* [commands to run] \0/'
    echo "* OK to proceed? [y/N]"
    read proceed
    if [ "y" == "$proceed" ]; then
      # Pass lines slowly into parted. Otherwise it gets backed up and throws a fit.
      cat "$SCRATCH"1 \
      | pv --quiet --line-mode --rate-limit 1 \
      | parted \
      | sed 's/.*/* [parted says] \0/'
      echo "* OK, commands were executed."
    else
      echo "* OK, no changes made"
    fi
    echo "* END OF INTERACTIVE COMMAND QUEUEING *"
  else
    echo "OK, no changes made."
  fi
else
  echo "ERROR: No changes possible. parted command not found."
  exit 1
fi

echo 
echo "------------------------------"
echo "-- Build New Partitions & Replace Existing Directories"
echo "------------------------------"
echo "Build new partitions? [y/N]"
read proceed
if [ "y" == "$proceed" ]; then
  echo "NOTE: Undo capability is fairly limited. We are erasing and rebuilding filesystems."
  echo "Press ^C to abort NOW."
  echo "-- press any key to continue --"
  read proceed
  # mkfs.ext4
  echo "* BEGIN INTERACTIVE COMMAND EXECUTION *"
  # Read cmds into $SCRATCH, replacing spaces with ~~ so that the for works right
  cat $DATA_DIR/filesystem_generation_cmds.txt \
  | grep --invert-match "^#" \
  | tr " \t" "~~" \
    > "$SCRATCH"
  made_changes="N"
  for cmd in `cat $SCRATCH`; do
    # Get spaces into the string again
    cmd=`echo $cmd | tr "~" " "`
    # Replace device names
    cmd=${cmd//_DEVICE_ROOT1_/$DEVICE_ROOT1}
    cmd=${cmd//_DEVICE_ROOT2_/$DEVICE_ROOT2}
    cmd=${cmd//_DEVICE_DATA1_/$DEVICE_DATA1}
    echo "* Run command below? [y/N]"
    echo "*" `echo $cmd | cat -A`
    read proceed
    if [ "y" == "$proceed" ]; then
      eval "$cmd"
      made_changes="Y"
      echo "* Action performed."
    else
      echo "* OK, command was ignored."
    fi
  done
  echo "* END OF INTERACTIVE COMMAND EXECUTION *"
  if [ $made_changes == "Y" ]; then
    echo "Partitions have changed."
    echo "Rebuilding run-time variable: PARTITIONS"
    PARTITIONS=`df --human-readable | grep ^/dev/xvd | awk '{print $NF}' | tr "\n" " "`
    echo "New value for partitions:"
    echo "$PARTITIONS"
    echo "-- press any key to continue --"
    read proceed
  else
    echo "OK, no commands were run."
  fi
else
  echo "OK, no changes made."
fi

echo 
echo "------------------------------"
echo "-- Add Partitions to fstab"
echo "------------------------------"
modfile=/etc/fstab
# just grab header comment for modflag
modflag=`cut --fields=2- $DATA_DIR/fstab_template.txt | head -1`
echo "Append template to end of fstab file? [y/N]"
read proceed
if [ "$proceed" == "y" ]; then
  modfilebak="$modfile".save-before_setup-`date +%F`
  if [ ! -e "$modfilebak" ]; then
    cp $modfile $modfilebak
  fi
  cat $DATA_DIR/fstab_template.txt \
  | sed "s/_DEVICE_ROOT1_/$DEVICE_ROOT1/g" \
  | sed "s/_DEVICE_ROOT2_/$DEVICE_ROOT2/g" \
  | sed "s/_DEVICE_DATA1_/$DEVICE_DATA1/g" \
    >> "$modfile" 
  echo "OK, displaying new fstab below:"
  echo "-- press any key to continue --"
  read proceed
  cat $modfile | sed 's/.*/'"[$modfile]"' \0/'
  cp $modfile $modfile.save-after_setup-`date +%F`
  >> $UNDO_FILE echo "echo 'Undoing fstab additions...' "
  >> $UNDO_FILE echo "sed --in-place '/^# $modflag/,+10000d' '$modfile'"
else
  echo "OK, no changes made."
fi

# That's All Folks

echo "------------------------------"
echo "-- Conclusion"
echo "------------------------------"
echo "- Partitioning finished."

exit 0
