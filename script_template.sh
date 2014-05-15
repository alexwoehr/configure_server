
echo "This script is just an example. Please do not try to run it."
exit 255

# INTRODUCTION
echo 
echo "=============================="
echo "== WELCOME TO ${0##*/}"
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
# - 99: Aborted at user request
# - 255: test abort (same as -1)

##########################
# Setup Variables
##########################
source ./setup_vars.sh \
|| (echo "Cannot find setup_vars.sh. Exiting..." && exit 3)

# Create files
> "$ACTIONS_TAKEN_FILE"

>  "$UNDO_FILE" echo "#!/bin/sh"
>> "$UNDO_FILE" echo            
chmod +x "$UNDO_FILE"

echo "------------------------------"
echo "-- Runtime Global Variables"
echo "------------------------------"
echo "- (see setup_vars.sh for definition)"
echo PARTITIONS "$PARTITIONS"
echo UNDO_FILE "$UNDO_FILE"
echo TMP_DIR "$TMP_DIR"
echo LIB_DIR "$LIB_DIR"
echo SCRATCH "$SCRATCH"
echo ACTIONS_COUNTER "$ACTIONS_COUNTER"
echo ACTIONS_TAKEN_FILE "$ACTIONS_TAKEN_FILE"
echo "-- press any key to continue --"
read proceed


# BASED ON SECTION TEMPLATE 0.2
# - 
#   type: SECTION
#   testing:
#     - minimum
#     - undo
#     - force fix
# [A] Basic variables for this section
# modflag: the name of the current section
modflag="Step 1.1.1A (1a)"
# modfile: the main file that is being modified within this step.
modfile="/chroot/nowhere/my-config"
# checkfile: if you aren't modifying a file, we will frequently set a "checkfile" which is the file to be checked pursuant to the current command.
checkfile="/chroot/nowhere/my-list"
# [B] Header
echo "---------------------"
echo "- $modflag"
echo "---------------------"
# [C] check if we need to make our change
echo "... Checking whether to make changes or not..."
cat "$modfile" \
| grep "^# $modflag$" \
  > $SCRATCH
if [[ ! -s $SCRATCH ]]; then
  echo "... No changes necessary."
else
  echo "... Changes not made yet."
  # [D] ask whether to make changes
  echo "... We found bad files. See below."
  cat $SCRATCH | sed 's/.*/[grep says] \0/'
  echo "... We found bad files. Enter interactive mode? [y/N]"
  read proceed
  if [[ $proceed != "y" ]]; then
    echo "... OK, no changes made."
  else
    # [E] backup modfile before making changes
    modfilebak="$modfile".save-before_setup-`date +%F`
    if [[ ! -e "$modfilebak" ]]; then
      cp $modfile $modfilebak
    fi
    # [F] interactive mode
    echo "file1 file2" > $SCRATCH
    for file in `cat $SCRATCH`; do
      echo "...... Fix file '$file'? [y/N]"
      read proceed
      if [[ $proceed != "y" ]]; then
        echo "...... OK, no changes made."
      else
        # [G] Action itself
        echo "...... Changing file '$file' ..."
        >> $file echo "# $modflag"
        >> $file echo "security=1"
        chmod ugo-w $file \
          && echo "...... Done." \
          || (echo "...... ERROR: Could not fix $file." && exit 1)
        echo "...... Done."
        # [H] Stat the action
        (( ++ACTIONS_COUNTER ))
        >> "$ACTIONS_TAKEN_FILE" echo $modflag "interactively for $file"
        # [I] Append to undo file
        >> $UNDO_FILE echo "echo '### $modflag ###' "
        >> $UNDO_FILE echo "echo 'Removing changes to $modfile...' "
        >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
        echo "...... Wrote undo file."
      fi
    done
    # [J] now backup current versions
    cp $modfile $modfile.save-after_setup-`date +%F`
  fi
fi
# [K] ensure they acknowledge the above before proceeding
echo "-- press enter when ready --"
read proceed
# End of Section Template

# Note: this blurb deals with the situation where modfile requires signoff.
while true; do
  # Check if they have signed off on changes yet.
  grep "^# CHANGES OK$" $modfile
    > $SCRATCH
  if [[ -s $SCRATCH ]]; then
    break
  fi
  echo "... signoff not found yet."
  echo "=== WARNING ==="
  echo "=== please ensure that pam.d/su is not botched!"
  echo "=== add following separate line to end of file to sign off on changes when you are done:"
  echo "# CHANGES OK"
  echo "=== quit with ^Z, then fg to return and hit enter."
  echo "-- press any key when ready --"
  read proceed
done
# Remove signoff in case file is modified again.
sed --in-place '/^# CHANGES OK$/d' $modfile

# Conclusion to the script

echo "------------------------------"
echo "-- Conclusion"
echo "------------------------------"
echo "- Actions Taken: $ACTIONS_COUNTER "
echo "- Actions Log: Press any key..."
read proceed
cat "$ACTIONS_TAKEN_FILE" | nl | sed 's/.*/[Actions Taken file] \0/'
echo "- END OF ACTIONS TAKEN FILE"
echo
echo "Please see $UNDO_FILE for ability to revert most of the changes we have made."
echo "-- press any key to end --"
read proceed

exit 0
