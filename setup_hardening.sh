#!/bin/bash

source ./ui.inc
source ./functions.inc

ui_section "WELCOME TO SECURITY HARDENING SCRIPT"

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
|| (ui_print_note "Cannot find setup_vars.sh. Exiting..." && exit 3)

# Create files
> "$ACTIONS_TAKEN_FILE"

>  "$UNDO_FILE" echo "#!/bin/sh"
>> "$UNDO_FILE" echo            
chmod +x "$UNDO_FILE"

ui_section "Runtime Global Variables"
ui_print_note "(See setup_vars.sh for definition.)"
echo  ".   PARTITIONS          $PARTITIONS"
echo  ".   UNDO_FILE           $UNDO_FILE"
echo  ".   TMP_DIR             $TMP_DIR"
echo  ".   LIB_DIR             $LIB_DIR"
echo  ".   SCRATCH             $SCRATCH"
echo  ".   ACTIONS_COUNTER     $ACTIONS_COUNTER"
echo  ".   ACTIONS_TAKEN_FILE  $ACTIONS_TAKEN_FILE"
ui_press_any_key

# SECTION
# - TESTING:
#   - basic
#   - basic centos
#   - basic debian
##########################
# SELinux and other prerequisites
##########################
ui_section "Check SELinux Status"

# Show to user
ui_print_note "SEStatus:"
sestatus \
| ui_highlight '(en|dis)abled' --extended-regexp \
| ui_escape_output "sestatus"

if ! fn_selinux_enabled; then
  ui_print_note "setup_hardening assumes that you use SELinux."
  ui_print_note "Please setup SELINUX on your own."
  if [ -e setup_selinux.sh ]; then
    ui_print_note "Congratulations! You're in luck! You should be able to run the script setup_selinux.sh. Try that first."
  fi
  ui_print_note "Quit script? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    ui_print_note "OK. Quitting."
    exit 99; # aborted
  fi
else
  ui_print_note "SELinux is enabled."
  ui_print_note "No changes necessary."
fi

ui_section "Runtime Environment & Directories"
modflag="configure_server create standard directories"
echo "Create our standard directories? [y/N]"
read proceed
if [[ "$proceed" == "y" ]]; then
  # TODO: move list of dirs into separate data file and have interactive confirmation of each dir
  # Default location to chroot users and others into
  dir="/chroot/nowhere"
  mkdir --parents $dir
  (( ++ACTIONS_COUNTER ))
  >> "$ACTIONS_TAKEN_FILE" echo $modflag
  # Append to undo file
  >> $UNDO_FILE echo "echo 'Undoing creation of '$dir'...' "
  >> $UNDO_FILE echo "rmdir '$dir' || echo 'Uh oh, someone has added files to' '$dir' 'already. Not removing.'"
else
  echo "OK, no changes made."
fi

# NSA 2.2.1 Remove Extra FS
# SECTION
# - TESTING:
#   - basic
#   - undo
ui_section "Remove Extra FS Types"
modfile="/etc/modprobe.d/configure_server.exclusions.modprobe.conf"
modflag="configure_server directive 2.2.1"

# Check whether this flag has been applied yet
if [ 0 == $( grep "$modflag"$ "$modfile" | wc -l) ]; then
  source <( 
    ui_prompt_macro "This task has not been done yet. Proceed? [y/N]" proceed n
  )

  if [ "$proceed" == "y" ]; then

    # Save old file
    source <(
      fn_backup_config_file_macro "$modfile" modfile_saveAfter_callback
    )

    for fs in usb-storage {cram,freevx,h,squash}fs jffs2 hfsplus udf; do
      >> "$modfile" echo "# $modflag"
      >> "$modfile" echo "install $fs /bin/true"
      ui_print_note "Removed unnecessary fs: $fs"
    done

    modfile_saveAfter_callback

    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Undoing FS disables...' "
    >> $UNDO_FILE echo "sed --in-place '/^# $modflag/,+1d' '$modfile'"
    ui_print_note "Wrote undo file."

  else
    ui_print_note "OK, did not proceed."
  fi
else
  ui_print_note "Already done. No action taken."
fi

# NSA 2.2.2 Permissions
# NSA 2.2.2.1
# SECTION
# - TESTING:
#   - basic
ui_section "Critical Password Files: Permissions"
ui_print_note "proceeding because no sane individual would refuse. Only sane individuals are allowed to run this script."
chown root:root /etc/{passwd,shadow,group,gshadow}
chmod 644 /etc/{passwd,group}
chmod 400 /etc/{shadow,gshadow}
ui_print_note "OK, done."

# NSA 2.2.2.2 World Writable Directories
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
ui_section "Fix World Writable Directories"
modfile=""
modflag="configure_server directive 2.2.2.2"

ui_start_task "Check for world writable directories"

# Create a results file to work through
results_file="$TMP_DIR/NSA.2.2.2.2.world_writable_dirs.txt"
> $results_file

# Find bad directories in each partition
find_worldwritable_dirs() {
  local readonly worldWritable="-0002"
  local readonly hasStickyBit="-1000"
  local PART
  for PART in $PARTITIONS; do
    find $PART -xdev -type d \( -perm $worldWritable -a ! -perm $hasStickyBit \) -print
  done >> $results_file
}
find_worldwritable_dirs

ui_end_task "Check for world writable directories"

# Interactive part
if [ ! -s $results_file ]; then
  ui_print_note "No offending directories found."
  ui_print_note "Nothing to do."
else

  source <(
    ui_prompt_macro "World-writable directories were found. Would you like to fix them interactively? [y/N/f]
(y = Yes, n = No, f = Force)" proceed n
  )

  if [ "$proceed" == "y" -o "$proceed" == "f" ]; then
    # Initiate interactive mode
    ui_start_task "Interactive world-writable fix"
    for dir in `cat $results_file`; do

      # Check for "force" mode
      if [ "$proceed" != "f" ]; then
        source <(
          ui_prompt_macro "* Set sticky bit for $dir? [y/N]" proceed2 n
        )
      else
        # we're in "force" mode, should use y for everything
        proceed2="y" # force to y for all of them
      fi

      if [ "$proceed2" == "y" ]; then
        ui_print_note "* Setting sticky bit on $dir..."
        chmod +t "$dir"
        ls -dlh "$dir" | ui_escape_output ls
        (( ++ACTIONS_COUNTER ))
        >> "$ACTIONS_TAKEN_FILE" echo $modflag
        # Append to undo file
        >> $UNDO_FILE echo "echo 'Undoing sticky bit set on $dir...' "
        >> $UNDO_FILE echo "chmod -t '$dir'"
        ui_print_note "* Wrote undo file."
      else
        ui_print_note "* OK, no action taken on $dir"
      fi

    done
    ui_end_task "Interactive world-writable fix"

  else
    ui_print_note "OK, skipping fixes."
  fi
fi

# NSA 2.2.2.3 World Writable Files
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
ui_section "Fix World Writable Files"
modfile=""
modflag="configure_server directive 2.2.2.3A"

ui_start_task "Check for world writable files"

# Create a results file with the files
results_file="$TMP_DIR/NSA.2.2.2.3.world_writable_files.txt"
> $results_file

# Find bad files in each partition
find_worldwritable_files() {
  local PART
  local readonly worldWritable="-0002"
  local readonly hasStickyBit="-1000"
  for PART in $PARTITIONS; do
    find $PART -xdev -type f \( -perm $worldWritable -a ! -perm $hasStickyBit \) -print
  done >> $results_file
}
find_worldwritable_files

ui_end_task "Check for world writable files"

# Interactive part
if [[ ! -s $results_file ]]; then
  ui_print_note "No offending files found."
  ui_print_note "Nothing to do."
else

  source <(
    ui_prompt_macro "World-writable files were found. Would you like to fix them interactively? [y/N/f]
(y = Yes, n = No, f = Force)" proceed n
  )

  if [ "$proceed" == "y" -o "$proceed" == "f" ]; then
    for file in `cat $results_file`; do

      # Check for "force" mode
      if [ "$proceed" != "f" ]; then
        source <(
          ui_prompt_macro "* Clear world writable permissions on $file? [y/N]" proceed2 n
        )
      else
        # we're in "force" mode, should use y for everything
        proceed2="y" # force to y for all of them
      fi

      if [ "$proceed2" == "y" ]; then
        ui_print_note "* Clearing world-writable permission on $file"
        chmod o-w "$file"
        ls -lh "$file" | ui_escape_output ls
        (( ++ACTIONS_COUNTER ))
        >> "$ACTIONS_TAKEN_FILE" echo $modflag
        # Append to undo file
        >> $UNDO_FILE echo "echo 'Undoing world writable reset for $file...' "
        >> $UNDO_FILE echo "chmod o+w '$file'"
        ui_print_note "* Wrote undo file."
      else
        ui_print_note "* OK, no action taken on $file"
      fi

    done
    ui_end_task "Interactive world-writable fix"

  else
    ui_print_note "OK, skipping fixes."
  fi
fi

# NSA 2.2.2.3 SUID / SGID permissions
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
ui_section "Fix SUID Executables"

ui_start_task "Check for unexpected setuid files"

modfile=""
modflag="configure_server directive 2.2.2.3A"

# Create a results file to work through
results_file="$TMP_DIR/NSA.2.2.2.4.suid.txt"
> $results_file

find_suid_files() {
  local readonly setuidPermissions="-4000"
  local PART
  for PART in $PARTITIONS; do
    find $PART -xdev \( -perm $setuidPermissions \) -type f -print
  done \
  | grep --invert-match --file="$DATA_DIR/suid_files_allow.txt" \
  | cat >> $results_file

  # Omit /chroot jails
  sed --in-place "/^\\/chroot\\//d" "$results_file"
}
find_suid_files

ui_end_task "Check for unexpected setuid files"

# Interactive part
if [ ! -s "$results_file" ]; then
  ui_print_note "No dangerous files found."
  ui_print_note "Nothing to do."
else
  source <(
    ui_prompt_macro "Unexpected setuid files were found. Would you like to review them interactively? [y/N/f]
(y = Yes, n = No, f = Force)" proceed n
  )

  if [ "$proceed" == "y" -o "$proceed" == "f" ]; then
    # Initiate interactive mode
    ui_start_task "Interactive setuid fix"
    for file in `cat "$results_file"`; do
      # Check for "force" mode
      if [ "$proceed" != "f" ]; then
        source <(
          ui_prompt_macro "* Clear setuid permission on $file? [y/N]" proceed2 n
        )
      else
        # we're in "force" mode, should use y for everything
        proceed2="y" # force to y for all of them
      fi

      if [ "$proceed2" == "y" ]; then
        ui_print_note "* Clearing setuid permission on $file..."
        chmod u-s "$file"
        (( ++ACTIONS_COUNTER ))
        >> "$ACTIONS_TAKEN_FILE" echo $modflag
        # Append to undo file
        >> $UNDO_FILE echo "echo 'Undoing suid removal on $file...' "
        >> $UNDO_FILE echo "chmod u+s '$file'"
        ui_print_note "* Wrote undo file."
      else
        ui_print_note "* OK, no action taken on $file"
      fi

    done
    ui_end_task "Interactive setuid fix"

  else
    ui_print_note "OK, skipping fixes."
  fi
fi

# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
ui_section "Fix SGID Executables"

ui_start_task "Check for unexpected setuid files"

modflag="configure_server directive 2.2.2.3B"

# Create a results file to work through
results_file="$TMP_DIR/NSA.2.2.2.4.sgid.txt"
> $results_file

find_sgid_files() {
  local readonly setgidPermissions="-2000"
  local PART
  for PART in $PARTITIONS; do
    find $PART -xdev \( -perm $setgidPermissions \) -type f -print
  done \
  | grep --invert-match --file="$DATA_DIR/suid_files_allow.txt" \
  | cat >> $results_file

  # Omit /chroot jails
  sed --in-place "/^\\/chroot\\//d" "$results_file"
}
find_sgid_files

ui_end_task "Check for unexpected setgid files"

# Interactive part
if [[ ! -s $results_file ]]; then
  ui_print_note "No dangerous files found."
  ui_print_note "Nothing to do."
else
  source <(
    ui_prompt_macro "Unexpected setgid files were found. Would you like to review them interactively? [y/N/f]
(y = Yes, n = No, f = Force)" proceed n
  )

  if [ "$proceed" == "y" -o "$proceed" == "f" ]; then
    # Initiate interactive mode
    ui_start_task "Interactive setgid fix"
    for file in `cat "$results_file"`; do
      # Check for "force" mode
      if [ "$proceed" != "f" ]; then
        source <(
          ui_prompt_macro "* Clear setgid permission on $file? [y/N]" proceed2 n
        )
      else
        # we're in "force" mode, should use y for everything
        proceed2="y" # force to y for all of them
      fi

      if [ "$proceed2" == "y" ]; then
        ui_print_note "* Clearing setgid permission on $file..."
        chmod g-s "$file"
        (( ++ACTIONS_COUNTER ))
        >> "$ACTIONS_TAKEN_FILE" echo $modflag
        # Append to undo file
        >> $UNDO_FILE echo "echo 'Undoing sgid removal on $file...' "
        >> $UNDO_FILE echo "chmod g+s '$file'"
        ui_print_note "* Wrote undo file."
      else
        ui_print_note "* OK, no action taken on $file"
      fi

    done
    ui_end_task "Interactive setgid fix"
  else
    ui_print_note "OK, skipping fixes."
  fi
fi

# NSA 2.2.4 Dangerous Execution Patterns
# NSA 2.2.4.1 umask
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo

ui_section "umask check"

# Check if operation has been performed yet
modfile="/etc/sysconfig/init"
modflag="configure_server directive 2.2.4.1"

if [ 0 == $( grep "$modflag"$ "$modfile" | wc -l) ]; then
  source <( 
    ui_prompt_macro "This task has not been done yet. Add umask restrictions? [y/N]" proceed n
  )

  if [ "$proceed" == "y" ]; then
    # Save old file
    source <(
      fn_backup_config_file_macro "$modfile" modfile_saveAfter_callback
    )

    echo "Setting umask sanely to 027.."
    >> $modfile echo "# $modflag"
    >> $modfile echo "umask 027"

    modfile_saveAfter_callback

    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Undoing umask set...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
    ui_print_note "Wrote undo file."

  else
    ui_print_note "OK, did not proceed."
  fi
else
  ui_print_note "Already done. No action taken."
fi

# NSA 2.2.4.2 Disable Core Dumps
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
ui_section "Disable Core Dumps"

ui_start_task "Disable Core Dumps via limits.conf"

modfile="/etc/security/limits.conf"
modflag="configure_server directive 2.2.4.2A"

# Check whether this flag has been applied yet
if [ 0 == $( grep "$modflag"$ "$modfile" | wc -l) ]; then
  source <( 
    ui_prompt_macro "This task has not been done yet. Proceed to disable core dumps in $modfile? [y/N]" proceed n
  )

  if [ "$proceed" == "y" ]; then
    # Save old file
    source <(
      fn_backup_config_file_macro "$modfile" modfile_saveAfter_callback
    )

    ui_print_note "Disabling core dumps via $modfile..."
    >> $modfile echo "# $modflag"
    >> $modfile echo "*        hard core 0"

    modfile_saveAfter_callback

    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Undoing core dump disablement on limits.conf...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
    ui_print_note "Wrote undo file."
  else
    ui_print_note "OK, did not proceed."
  fi
else
  ui_print_note "Already done. No action taken."
fi

ui_end_task "Disable Core Dumps via limits.conf"

ui_start_task "Disable Core Dumps via sysctl.conf"

modfile="/etc/sysctl.conf"
modflag="configure_server directive 2.2.4.2B"

# Check whether this flag has been applied yet
if [ 0 == $( grep "$modflag"$ "$modfile" | wc -l) ]; then
  source <( 
    ui_prompt_macro "This task has not been done yet. Proceed to disable core dumps in $modfile? [y/N]" proceed n
  )

  if [ "$proceed" == "y" ]; then
    # Save old file
    source <(
      fn_backup_config_file_macro "$modfile" modfile_saveAfter_callback
    )

    ui_print_note "Disabling core dumps via $modfile..."
    >> $modfile echo "# $modflag"
    >> $modfile echo "fs.suid_dumpable = 0"

    modfile_saveAfter_callback

    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Undoing core dump disablement on $modfile...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
    ui_print_note "Wrote undo file."
  else
    ui_print_note "OK, did not proceed."
  fi
else
  ui_print_note "Already done. No action taken."
fi

ui_end_task "Disable Core Dumps via sysctl.conf"

# NSA 2.2.4.3 execshield
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
ui_section "ExecShield"

modfile="/etc/sysctl.conf"
modflag="configure_server directive 2.2.4.3"

# Check whether this flag has been applied yet
if [ 0 == $( grep "$modflag"$ "$modfile" | wc -l) ]; then
  source <( 
    ui_prompt_macro "Enable execshield in $modfile? [y/N]" proceed n
  )

  if [ "$proceed" == "y" ]; then
    # Save old file
    source <(
      fn_backup_config_file_macro "$modfile" modfile_saveAfter_callback
    )

    ui_print_note "Enabling ExecShield.."
    >> $modfile echo "# $modflag"
    >> $modfile echo "kernel.exec-shield = 1" 
    >> $modfile echo "# $modflag"
    >> $modfile echo "kernel.randomize_va_space = 1"

    modfile_saveAfter_callback

    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Undoing exec-shield enable...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
    ui_print_note "Wrote undo file."
  else
    ui_print_note "OK, did not proceed."
  fi
else
  ui_print_note "Already done. No action taken."
fi

# NSA 2.2.4.5 prelink
# does not exist on this server; code below is untested
####    echo "------------------------------"
####    echo "-- prelink"
####    echo "------------------------------"
####    echo "Disable prelink? [y/N]"
####    read proceed
####    if [[ $proceed == "y" ]]; then
####      modfile="/etc/sysconfig/prelink"
####      # Save old file
####      modfilebak="$modfile".save-before_setup-`date +%F`
####      if [ ! -e "$modfilebak" ]; then
####        cp $modfile $modfilebak
####      fi
####      modflag="configure_server directive 2.2.4.5"
####      cat "$modfile" 
####      | grep "$modflag"$ \
####      | tee $SCRATCH \
####      && if [ ! -s $SCRATCH ]; then
####        echo "Disabling PreLink.."
####        >> $modfile echo "# $modflag"
####        >> $modfile echo "PRELINKING=no" 
####        # Save new file
####        cp $modfile $modfile.save-after_setup-`date +%F`
####        /usr/sbin/prelink -ua
####        (( ++ACTIONS_COUNTER ))
####        >> "$ACTIONS_TAKEN_FILE" echo $modflag
####        # Append to undo file
####        >> $UNDO_FILE echo "echo 'Undoing prelink disable...' "
####        >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
####      else
####        echo "Already done. No action taken."
####      fi
####    else
####      echo "Not changed."
####    fi

# NSA 2.3.1.1 Restrict Root Logins to System Console
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo

ui_section "Restrict Root Logins to System Console "

modfile="/etc/securetty"
modflag="configure_server directive 2.3.1.1"

cat "$modfile" \
| grep --invert-match --extended-regexp --file="$DATA_DIR/securetty_allowed.txt" \
  > "$SCRATCH"

if [ 0 '==' $(wc -l < "$SCRATCH") ]; then 
  ui_print_note "No unexpected terminals found."
  ui_print_note "Nothing to do."
else
  ui_print_note "The following extraneous consoles have been discovered:"
  ui_print_list "$SCRATCH"

  source <(
    ui_prompt_macro "Remove these items interactively? [y/N/f]
(y = Yes, n = No, f = Force all)" proceed n
  )

  if [ "$proceed" == "y" -o "$proceed" == "f" ]; then
    # Initiate interactive mode
    ui_start_task "Interactive console removal"

    # Save old file
    source <(
      fn_backup_config_file_macro "$modfile" modfile_saveAfter_callback
    )

    handle_item() {
      local item="$*" # one at a time

      # Check for "force" mode
      if [ "$proceed" != "f" ]; then
        # Ask
        source <(
          ui_prompt_macro "* Evict $item? [y/N]" proceed2 n
        )
      else
        # we're in "force" mode, should use y for everything
        proceed2="y" # force to y for all of them
      fi

      # Generate sed commands by generating line numbers and tacking "d" command on the end.
      generate_delete_script() {
        local file="$1"
        local search="$2"
        cat "$file" \
        | grep --line-number --fixed-strings "$search" \
        | cut -f1 -d: \
        | sed 's/$/d/' \
        | tac
      }

      if [ "$proceed2" == "y" ]; then
        ui_print_note "* Evicting $item from file..."
        sed --in-place --file=<( generate_delete_script "$modfile" "$item" ) "$modfile"
        (( ++ACTIONS_COUNTER ))
        >> "$ACTIONS_TAKEN_FILE" echo $modflag

        # Append to undo file
        >> $UNDO_FILE echo   "echo 'Re-adding removed console $item...' "
        >> $UNDO_FILE echo ">> '$modfile' echo '$item'"
        ui_print_note "* Wrote undo file."
      else
        ui_print_note "* OK, no action taken on $item"
      fi
    }

    # Execute our subroutine on each item
    source <(
      cat "$SCRATCH" \
      | sed 's/^/handle_item /'
    )

    # Backup copy of new file we have created
    modfile_saveAfter_callback

  else
    ui_print_note "OK, did not proceed."
  fi

fi

# NSA 2.3.1.2 Limit su Access to the Root Account
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
ui_section "Limit su Access to the Root Account"
modfile="/etc/group"
modflag="configure_server directive 2.3.1.2A"
readonly wheelgroup=wheel
ui_start_task "Create wheel group"

grep "^$wheelgroup:" "$modfile" \
  > $SCRATCH
if [ 0 == $(grep "^$wheelgroup:" "$modfile" | wc -l ) ]; then 
  source <( 
    ui_prompt_macro "There is no $wheelgroup group. Create it? [y/N]" proceed n
  )

  if [ "$proceed" == "y" ]; then
    ui_print_note "Adding new group..."

    # Add group
    groupadd "$wheelgroup"

    # Restrict users from entering group via newgrp or chgrp
    gpasswd --restrict "$wheelgroup"

    ui_print_note "OK, created '$wheelgroup' group."

    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Removing added $wheelgroup group...' "
    >> $UNDO_FILE echo "groupdel '$wheelgroup'"
  else
    echo "OK, no changes made."
  fi
else
  echo "No changes necessary."
fi

ui_end_task "Create wheel group"

ui_start_task "Restrict sudo to wheel via pam"

# [A] Variables
modflag="configure_server directive 2.3.1.2B"
modfile="/etc/pam.d/su"

# [B] Header
ui_start_task "$modflag: Add sudo wheel permissions to pam"

# [C] check if we need to make our change
if [ 0 '<' $( grep "$modflag"$ "$modfile" | wc -l) ]; then
  ui_print_note "Already done. No action taken."
else
  # [D] ask whether to make changes
  source <( 
    ui_prompt_macro "This task has not been done yet. Proceed to restrict sudo permissions to wheel via $modfile? [y/N]" proceed n
  )

  if [ "$proceed" != "y" ]; then
    ui_print_note "OK, did not proceed."
  else

    # [E] backup modfile before making changes
    source <(
      fn_backup_config_file_macro "$modfile" modfile_saveAfter_callback
    )

    ui_print_note "Changing $modfile ..."

    # Generate sed script to add line for wheel requirement
    pam_add_wheel_req_script() {
      local line="$1"
      # Stacking behavior -- required or requisite typically
      local stacking="${2:-required}"
      # command to append a line
      echo "${line} a\\"
      # new line: modflag
      echo "# $modflag\\"
      # new line: new configuration line
      echo "auth	$stacking	pam_wheel.so use_uid"
    }

    # File (filename after removing directory)
    pam_file="${modfile##*/}"

    # Line number to change
    pam_wheel_line="$(pam_find_wheel "$pam_file")"

    # Get stacking behavior: required or requisite
    pam_wheel_stacking=`pam_get_stacking "$pam_file" "$pam_wheel_line"`

    # Generate and execute sed script
    sed --in-place --file=<( pam_add_wheel_req_script "$pam_wheel_line" "$pam_wheel_stacking" ) "$modfile"

    modfile_saveAfter_callback

    # [H] Stat the action
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo "$modflag"
    # [I] Append to undo file
    >> $UNDO_FILE echo "echo '### $modflag ###' "
    >> $UNDO_FILE echo "echo 'Removing wheel restriction from $modfile...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
    ui_print_note "Wrote undo file."
  fi
fi

ui_end_task "$modflag: Add sudo wheel permissions to pam"

# NSA 2.3.1.3 Conﬁgure sudo to Improve Auditing of Root Access
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
ui_section "Limit sudo privileges for only $wheelgroup via sudoers"

modfile="/etc/sudoers"
modflag="configure_server directive 2.3.1.3"

if [ 0 '<' $( grep "$modflag"$ "$modfile" | wc -l) ]; then
  ui_print_note "No changes necessary."
else

  source <( 
    ui_prompt_macro "This task has not been done yet. Proceed to restrict sudo permissions to wheel via $modfile? [y/N]" proceed n
  )

  if [ "$proceed" != "y" ]; then
    ui_print_note "OK, did not proceed."
  else

    #backup
    source <(
      fn_backup_config_file_macro "$modfile" modfile_saveAfter_callback
    )

    # Find line number containing root privileges
    sudoers_find_root() {
      # Print out the line number for the line we are looking for
      cat "/etc/sudoers" | awk '/^root.*ALL.*ALL.*ALL/ { print FNR; exit }'
    }

    # Add line for wheel permission
    sudoers_add_wheel_req_script() {
      local line="$1"
      # command to append a line
      echo "${line} a\\"
      # new line: modflag
      echo "# $modflag\\"
      # new line: new configuration line
      echo "%wheel	ALL=(ALL)	ALL"
    }

    sed --in-place --file=<( sudoers_add_wheel_req_script $(sudoers_find_root) ) /etc/sudoers

    modfile_saveAfter_callback

    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag

    # Append to undo file
    >> $UNDO_FILE echo "echo 'Removing wheel group sudoers enablement...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
    ui_print_note "Wrote undo file."
  fi
fi

# NSA 2.3.1.4 Block Shell and Login Access for Non-Root System Accounts
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
ui_section "Block Shell and Login Access for Non-Root System Accounts"

modfile="/etc/passwd"
modflag="configure_server directive 2.3.1.4"

# Users to block login (set login to /sbin/nologin)
# - system users or ftp users
# - not already nologin
# - not narcissistic
fn_parse_system_users \
| union      <( fn_parse_ftp_users ) \
| sort | uniq \
| difference <( fn_parse_nologin_users | sort ) \
| difference <( fn_parse_narcissist_users | sort ) \
  > "$SCRATCH"_to_block

# Users to lock
# - system users
# - not already locked
fn_parse_system_users \
| union      <( fn_parse_ftp_users ) \
| sort | uniq \
| difference <( fn_parse_locked_users | sort ) \
| difference <( fn_parse_narcissist_users | sort ) \
  > "$SCRATCH"_to_lock

if [ 0 == `cat "$SCRATCH"_to_{b,}lock | wc -l` ]; then 
  ui_print_note "No offending users found."
else
  ui_print_note "Following accounts should be locked and/or blocked:"
  ui_print_list <( sort "$SCRATCH"_to_{b,}lock | uniq)

  source <( 
    ui_prompt_macro "Interactively lock these non-human users and block access? [y/N/f]" proceed n
  )

  if [ "$proceed" != "y" ]; then
    ui_print_note "OK, did not proceed."
  else
    #backup
    source <(
      fn_backup_config_file_macro "$modfile" modfile_saveAfter_callback
    )

    ui_start_task "Interactive block login"

    for acct in `cat "$SCRATCH"_to_block`; do
      if [ "$proceed" != "f" ]; then
        source <(
          ui_prompt_macro "* Block access to account '$acct'? [y/N]" proceed2 n
        )
      else
        # we're in "force" mode, should use y for everything
        proceed2="y" # force to y for all of them
      fi

      if [ "$proceed2" == "y" ]; then
        # Grab last field as login
        oldlogin="$(fn_get_user_login $acct)"
        usermod --shell /sbin/nologin "$acct"
	ui_print_note "* Blocked access to '$acct'."
        >> $UNDO_FILE echo "usermod --shell '$oldlogin' '$acct' "
	ui_print_note "* Wrote undo file."
      else
        echo "OK, no action taken."
      fi
    done

    ui_end_task "Interactive block login"

    ui_start_task "Interactive lock passwords"

    for acct in `cat "$SCRATCH"_to_lock`; do
      if [ "$proceed" != "f" ]; then
        source <(
          ui_prompt_macro "* Lock password for account '$acct'? [y/N]" proceed2 n
        )
      else
        # we're in "force" mode, should use y for everything
        proceed2="y" # force to y for all of them
      fi

      if [ "$proceed2" == "y" ]; then
	ui_print_note "* Locked password for '$acct'."
        usermod --lock $acct
        >> $UNDO_FILE echo "usermod --unlock '$acct'"
	ui_print_note "Wrote undo file."
      else
        ui_print_note "OK, no action taken."
      fi
    done

    ui_end_task "Interactive lock passwords"

    modfile_saveAfter_callback

  fi

fi

# NSA 2.3.1.5 Verify Proper Storage and Existence of Password Hashes
# SECTION
# - TESTING:
#   - basic
ui_section "Verify Proper Storage and Existence of Password Hashes"

ui_start_task "Step 1: Ensure no empty passwords"

checkfile="/etc/shadow"
modflag="configure_server directive 2.3.1.5A"
# List accounts that should definitely be locked
cat "$checkfile" \
| awk --field-separator=":" '($2 == "") {print $1}' \
  > "$SCRATCH"
if [ 0 == `cat "$SCRATCH" | wc -l` ]; then 
  ui_print_note "No empty passwords found."
else
  ui_print_note "Passwords are empty for following accounts:"
  ui_print_list $SCRATCH
  echo "Reenter passwords for these users? [y/N]"
  source <(
    ui_prompt_macro "Reenter passwords for these users? [y/N]" proceed n
  )

  if [ "$proceed" != "y" ]; then
    ui_print_note "OK, did not proceed."
  else
    # Set passwords for all of them
    cat $SCRATCH | xargs --max-args=1 --delimiter="\n" passwd
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag

    # Append to undo file
    >> $UNDO_FILE echo "echo 'Following users had empty passwords, not reverting...' "
    >> $UNDO_FILE ui_print_list "$SCRATCH" 
    ui_print_note "Wrote undo file (with no-op)."
  fi
fi

ui_end_task "Step 1: Ensure no empty passwords"

# SECTION
# - TESTING:
#   - basic

ui_start_task "Step 2: Ensure no passwords in passwd file"
ui_print_note "[untested b/c highly unlikely]"

checkfile="/etc/passwd"
modflag="configure_server directive 2.3.1.5B"
# List accounts that should definitely be locked
cat $checkfile \
| awk --field-separator=":" '($2 != "x") {print $1}' \
  > $SCRATCH
if [ 0 == `cat "$SCRATCH" | wc -l` ]; then 
  ui_print_note "No offending users found."
else
  ui_print_note "WARNING"
  ui_print_note "Invalid passwords for following users were discovered:"
  ui_print_list "$SCRATCH"
  source <( 
    ui_prompt_macro  "Reenter passwords for these users? [y/N]" proceed n
  )

  if [ "$proceed" != "y" ]; then
    ui_print_note "OK, did not proceed."
  else
    # Reset all passwords
    ui_print_note "OK, resetting these passwords."
    cat "$SCRATCH" | xargs --max-args=1 --delimiter="\n" passwd

    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag

    # Append to undo file
    >> $UNDO_FILE echo "echo 'Following users had passwords in wrong place. Passwords were changed...' "
    >> $UNDO_FILE sed 's/^/echo - /' "$SCRATCH"
    ui_print_note "Wrote undo file (with no-op)."
  fi
fi

ui_end_task "Step 2: Ensure no passwords in passwd file"

# NSA 2.3.1.6 Verify that No Non-Root Accounts Have UID 0
# SECTION
# - TESTING:
#   - basic
ui_section "Verify that No Non-Root Accounts Have UID 0"
ui_print_note "[untested because it is a very unlikely scenario]"

checkfile="/etc/passwd"
modflag="configure_server directive 2.3.1.6"
cat "$checkfile" \
| awk --field-separator=":" '$3 == "0" && $1 != "root" {print $1}' \
  > "$SCRATCH"
if [ 0 == `cat "$SCRATCH" | wc -l` ]; then 
  ui_print_note "No offending users found."
else
  ui_print_note "Following accounts have invalid user id and should be removed:"
  ui_print_list "$SCRATCH"

  source <( 
    ui_prompt_macro "Interactively remove these users? [y/N]" proceed n
  )

  if [ "$proceed" != "y" ]; then
    ui_print_note "OK, did not proceed."
  else

    #backup some information
    source <(
      fn_backup_config_file_macro "$modfile" modfile_saveAfter_callback
    )

    ui_start_task "Interactively remove users"

    for acct in `cat "$SCRATCH"`; do
      source <(
        ui_prompt_macro "* DELETE account '$acct'? [y/N]" proceed2 n
      )

      if [ "$proceed2" == "y" ]; then
        # Grab last field as login
        ui_print_note "You must run this command:"
        echo "userdel '$acct' && fg"
        ui_print_note "Press Ctrl+Z, run the command, then hit enter."
        ui_press_any_key

        # Check if they successfully removed the file.
        if [ 0 == `grep "^$acct:" /etc/passwd | wc -l` ]; then
          ui_print_note "OK, account has been removed."
        else 
          ui_print_note "WARNING! You did not run the command. Please execute hardening script again."
        fi

        >> $UNDO_FILE echo "echo '$modflag'"
        >> $UNDO_FILE echo "echo 'The following account was removed. See modfile backup for info.'"
        >> $UNDO_FILE echo "echo - '$acct'"

	ui_print_note "* Wrote undo file."
      else
        echo "OK, no action taken."
      fi
    done

    ui_end_task "Interactively remove users"

    modfile_saveAfter_callback

  fi

fi

# NSA 2.3.1.7 Set Password Expiration Date Parameters
# not implementing...

ui_print_note "Skipping following directive as it is deemed unnecessary..."
echo "NSA 2.3.1.7 Set Password Expiration Date Parameters"
ui_press_any_key

# NSA 2.3.1.8 Remove Legacy + Entries from Password Files
# SECTION
# - TESTING:
#   - basic
ui_section "Remove Legacy + Entries from Password Files"
ui_print_note "[untested because it is a very unlikely scenario]"

checkfiles=/etc/{passwd,shadow,group}
modflag="configure_server directive 2.3.1.8"

eval "grep '^+:' $checkfiles" \
  > "$SCRATCH"
if [ 0 == `cat "$SCRATCH" | wc -l` ]; then 
  ui_print_note "No offending users found."
else

  ui_print_note "WARNING"
  ui_print_note "Invalid passwords for following users were discovered:"
  ui_print_list "$SCRATCH"
  source <( 
    ui_prompt_macro  "Reenter passwords for these users? [y/N]" proceed n
  )

  if [ "$proceed" != "y" ]; then
    ui_print_note "OK, did not proceed."
  else
    # Reset all passwords
    ui_print_note "OK, resetting these passwords."
    cat "$SCRATCH" | xargs --max-args=1 --delimiter="\n" passwd

    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag

    # Append to undo file
    >> $UNDO_FILE echo "echo 'Following users had passwords in wrong place. Passwords were changed...' "
    >> $UNDO_FILE sed 's/^/echo - /' "$SCRATCH"
    ui_print_note "Wrote undo file (with no-op)."
  fi
fi

# NSA 2.3.2.2 Create and Maintain a Group Containing All Human Users
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
ui_section "Create and Maintain a Group Containing All Human Users"

checkfile="/etc/group"
modfile=""
modflag="configure_server directive 2.3.2.2A"
humansgroup=humans

ui_start_task "Step 1. Create humans group"

grep "^$humansgroup:" "$checkfile" \
  > $SCRATCH
if [ 0 '<' `cat "$SCRATCH" | wc -l` ]; then
  ui_print_note "Found group '$humansgroup'. Nothing to do."
else
  source <(
    ui_prompt_macro  "No humans group ('$humansgroup') was found. Create it? [y/N]" proceed n
  )

  if [ "$proceed" == "y" ]; then
    ui_print_note "OK, no changes made."
  else

    # Add group
    groupadd "$humansgroup"

    # Restrict users from entering group via newgrp or chgrp
    gpasswd --restrict "$humansgroup"

    ui_print_note "OK, created '$humansgroup' group."

    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag

    # Append to undo file
    >> $UNDO_FILE echo "echo 'Removing added '$humansgroup' group...' "
    >> $UNDO_FILE echo "groupdel '$humansgroup'"

    ui_print_note "Wrote undo file."
  fi
fi

ui_end_task "Step 1. Create humans group"

ui_start_task "Step 2. Add users to humans group."

# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
checkfile="/etc/passwd"
modfile=""
modflag="configure_server directive 2.3.2.2B"
if [ "" == `fn_does_group_exist_yn "$humansgroup"` ]; then

  ui_print_note 'No humans group found. Skipping.'

else

  ui_print_note "Looking for prospective human users..."

  # Find users that aren't in humans but should be.

  # Prime the pump
  > "$SCRATCH"
  echo "root" >> "$SCRATCH"

  # Add more people
  cat "$checkfile" \
  | cut --fields=1 --delimiter=":" \
  | sort \
  | difference <( fn_list_addl_users_in_group "$humansgroup" | sort ) \
  | difference <( fn_parse_system_users | sort ) \
  | difference <( fn_parse_ftp_users | sort ) \
  | sort | uniq \
    >> $SCRATCH

  if [ 0 == `cat "$SCRATCH" | wc -l` ]; then
    ui_print_note "No potentially human users found, that are not already added."
  else
    ui_print_note "These possibly human users were found:"
    ui_print_list "$SCRATCH"

    source <(
      ui_prompt_macro "Interactively confirm to add them? [y/N]" proceed n
    )

    if [ "$proceed" != "y" ]; then
      ui_print_note "OK, skipping."
    else

      ui_start_task "Interactively add human users"

      for acct in `cat "$SCRATCH"`; do
        if [ "$proceed" != "f" ]; then
          source <(
            ui_prompt_macro "* Add user '$acct' to group '$humansgroup'? [y/N]" proceed2 n
          )
        else
          # we're in "force" mode, should use y for everything
          proceed2="y" # force to y for all of them
        fi

        if [ "$proceed2" == "y" ]; then
          gpasswd --add "$acct" "$humansgroup"
          ui_print_note "* Added user '$acct' to '$humansgroup'."

          (( ++ACTIONS_COUNTER ))
          >> "$ACTIONS_TAKEN_FILE" echo $modflag "(account $acct)"

          >> $UNDO_FILE echo "echo 'Removing user '$acct' from '$humansgroup'..."
          >> $UNDO_FILE echo "gpasswd --delete '$acct' '$humansgroup' "
          ui_print_note "* Wrote undo file."
        else
          echo "OK, no action taken."
        fi
      done

      ui_end_task "Interactively add human users"

    fi
  fi
fi

ui_end_task "Step 2. Add users to humans group."

# NSA 2.3.3.1 Set Password Quality Requirements
ui_section "Set Password Quality Requirements"

modfile="/etc/pam.d/system-auth"
modflag="configure_server directive 2.3.3.1"
if [ 0 '<' `grep "$modflag"$ "$modfile" | wc -l` ]; then
  ui_print_note "Requirements already set."
else
  source <(
    ui_prompt_macro "This task has not been done yet. Proceed to modify password quality requirements? [y/N]" proceed n
  )

  if [ "$proceed" != "y" ]; then
    ui_print_note "OK, did not proceed."
  else

    # Save backup
    source <(
      fn_backup_config_file_macro "$modfile" modfile_saveAfter_callback
    )

    # Generate sed script to add line for wheel requirement
    pam_add_cracklib_script() {
      # Line to change
      local line="$1"
      # Stacking behavior -- required or requisite typically
      local stacking="${2:-requisite}"
      # Comment
      local comment="$3"
      # command to append a line
      echo "${line} a\\"
      if [ -n "$3" ]; then
        # new line: comment annotation
        echo "# $comment\\"
      fi
      # new line: new configuration line
      echo "password	$stacking	pam_cracklib try_first_pass retry=3 minlen=14 dcredit=-1 ucredit=-1 ocredit=-1 lcredit=-1"
    }

    # File (filename after removing directory)
    pam_file="${modfile##*/}"

    # Line number to change
    pam_cracklib_line="$(pam_find_cracklib "$pam_file")"

    # Get stacking behavior: required or requisite
    pam_cracklib_stacking=`pam_get_stacking "$pam_file" "$pam_cracklib_line"`

    # Generate and execute sed script
    sed --in-place --file=<( pam_add_cracklib_script "$pam_cracklib_line" "$pam_cracklib_stacking" "$modflag" ) "$modfile"

    modfile_saveAfter_callback

    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Removing password quality requirements...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
    ui_print_note "Wrote undo file."
  fi
fi

# NSA 2.3.4.1 Ensure that No Dangerous Directories Exist in Root's Path
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
ui_section "Ensure that No Dangerous Directories Exist in Root's Path"
echo "Please modify your bash file to edit the path, if desired."
echo "Press Enter to continue..."
ui_press_any_key
ui_print_note "OK, no changes made."

# NSA 2.3.4.1.2 skipped
# NSA 2.3.4.2 skipped
# NSA 2.3.4.3 skipped
# NSA 2.3.4.4 skipped
# NSA 2.3.5.1-4 skipped

# NSA 2.3.5.5  Implement Inactivity Time-out for Login Shells
# NOTES: currently 10 hours
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
ui_section "Implement Inactivity Time-out for Login Shells"

modfile="/etc/profile.d/tmout.sh"
modflag="configure_server directive 2.3.5.5"

if [ -e "$modfile" ]; then
  ui_print_note "Inactivity script already present. No action taken."
else
  source <(
    ui_prompt_macro   "Inactivity timeout file is not created. Create it? [y/N]" proceed n
  )

  if [ "$proceed" == "y" ]; then
    # Create script
    >  $modfile cat <<<END_SCRIPT
#!/bin/bash
# $modflag
TMOUT=36000
# $modflag
readonly TMOUT
# $modflag
export TMOUT
END_SCRIPT

    # Set permissions on script
    chown root:root "$modfile"
    chmod u+rwx "$modfile"
    echo "Created '$modfile'. Contents:"

    cat "$modfile" | ui_escape_output 'cat'

    # Save new file
    cp $modfile $modfile.save-after_setup-`date +%F`

    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo "$modflag"

    # Append to undo file
    >> $UNDO_FILE echo "echo 'Removing inactivity timeout for login shells file...' "
    >> $UNDO_FILE echo "rm '$modfile'"

  fi
fi

# NSA 2.3.5.6-7 skipped
# NSA 2.3.6 skipped

# NSA 2.3.7.1 Warning Banners for System Accesses
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
ui_section "Warning Banners for System Accesses"
ui_print_note "Two files to check: issue and issue.net"
if [ -n `ls /etc/issue{,.net}` ]; then
  ui_print_note "No banners files found."
  ui_print_note "Nothing to do."
else
  modflag="configure_server directive 2.3.6"
  for modfile in /etc/issue{,.net}; do
    if [ -s "$modfile" ]; then
      source <(
        ui_prompt_macro  "Login banner '$modfile' has info. Remove it? [y/N]" proceed n
      )

      if [ "$proceed" != "y" ]; then
        ui_print_note "OK, $modfile not removed."
      else
        source <(
          fn_backup_config_file_macro "$modfile" modfile_saveAfter_callback
        )

        # Empty file
        >  $modfile

        modfile_saveAfter_callback

        (( ++ACTIONS_COUNTER ))
        >> "$ACTIONS_TAKEN_FILE" echo "$modflag"

        # Append to undo file
        >> $UNDO_FILE echo "echo \"Re-adding the banner '$modfile'...\" "
        >> $UNDO_FILE echo "cp '$modfilebak' '$modfile'"
        ui_print_note "Wrote undo file."
      fi
    fi
  done
fi

# NSA 2.3.7.2 skipped

# NSA 2.4 SELINUX
# see top of file

# NSA 2.5.1.1 Kernel Parameters which Affect Networking: Network Parameters for Hosts Only
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
ui_section "Kernel Parameters which Affect Networking: Network Parameters for Hosts Only"

modfile="/etc/sysctl.conf"
modflag="configure_server directive 2.5.1.1"

if [ 0 '<' $(grep "$modflag"$ "$modfile" | wc -l) ]; then
  ui_print_note "Changes already made. Nothing to do."
else
  source <(
    ui_prompt_macro "We have not yet changed forwarding in '$modfile'. Change it? [y/N]" proceed n
  )

  if [ "$proceed" != "y" ]; then
    ui_print_note "OK, no changes made."
  else

    source <(
      fn_backup_config_file_macro "$modfile" modfile_saveAfter_callback
    )

    >> "$modfile" cat <<END_FLAGS
# $modflag
net.ipv4.ip forward = 0
# $modflag
net.ipv4.conf.all.send redirects = 0
# $modflag
net.ipv4.conf.default.send redirects = 0
END_FLAGS

    ui_print_note "OK, $modfile changed."

    # Save new file
    modfile_saveAfter_callback

    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Removing forwarding prevention rules...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
    ui_print_note "Wrote undo file."
  fi
fi

# NSA 2.5.1.2 Kernel Parameters which Affect Networking: Network Parameters for Hosts and Routers
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
ui_section "Kernel Parameters which Affect Networking: Network Parameters for Hosts and Routers"

modfile="/etc/sysctl.conf"
modflag="configure_server directive 2.5.1.2"

if [ 0 '<' `grep "$modflag"$ "$modfile | wc -l` ]; then
  ui_print_note "Changes already made. Nothing to do."
else
  source <(
    ui_prompt_macro "We have not yet added these restrictions to '$modfile'. Change it? [y/N]" proceed n
  )

  if [ "$proceed" != "y" ]; then
    ui_print_note "OK, skipping."
  else
    # Backup old file
    source <(
      fn_backup_config_file_macro "$modfile" modfile_saveAfter_callback
    )

    >> "$modfile" cat <<END_FLAGS
# $modflag
net.ipv4.conf.all.log_martians = 1
# $modflag
net.ipv4.conf.all.accept_source_route = 0
# $modflag
net.ipv4.conf.all.accept_redirects = 0
# $modflag
net.ipv4.conf.all.secure_redirects = 0
# $modflag
net.ipv4.conf.all.log_martians = 1
# $modflag
net.ipv4.conf.default.accept_source_route = 0
# $modflag
net.ipv4.conf.default.accept_redirects = 0
# $modflag
net.ipv4.conf.default.secure_redirects = 0
# $modflag
net.ipv4.icmp_echo_ignore_broadcasts = 1
# $modflag
net.ipv4.icmp_ignore_bogus_error_messages = 1
# $modflag
net.ipv4.tcp_syncookies = 1
# $modflag
net.ipv4.conf.all.rp_filter = 1
# $modflag
net.ipv4.conf.default.rp_filter = 1
END_FLAGS

    ui_print_note "Added restrictions."

    modfile_saveAfter_callback

    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag

    # Append to undo file
    >> $UNDO_FILE echo "echo 'Removing $modflag sysctl restrictions for hosts / routers ...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
  fi
fi

# NSA 2.5.1.3 Ensure System is Not Acting as a Network Sniffer
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
ui_section "Ensure System is Not Acting as a Network Sniffer"

checkfile="/proc/net/packet"
modfile=""
modflag="configure_server directive 2.5.1.2"
if [ 1 '<' `cat /proc/net/packet | wc -l` ]; then
  ui_print_note "System looks normal."
else
  echo "Here is the packet file."
  cat /proc/net/packet | nl | sed 's/.*/* \0/'

  source <(
    ui_prompt_macro "Abort and investigate? [y/N]" proceed n
  )

  if [ "$proceed" != "y" ]; then
    ui_print_note "OK, no changes made."
  else
    exit 99 # aborted
  fi
fi

# NSA 2.5.4 skipped

# NSA 2.5.5 iptables
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
ui_section "IPTABLES"

modfile=/etc/sysconfig/iptables
modflag="configure_server directive 2.5.5A iptables"
ui_start_task "Step 1: Copy sample file"
source <(
  ui_prompt_macro "Copy the iptables sample to the config directory? [y/N]" proceed n
)
if [ "$proceed" != "y" ]; then
  ui_print_note "OK, no changes made."
else
  source <(
    fn_backup_config_file_macro "$modfile" modfile_saveAfter_callback
  )

  cp "$LIB_DIR"/samples/iptables /etc/sysconfig/iptables

  ui_print_note "Please inspect the new iptables firewall."
  ui_press_any_key

  modfile_saveAfter_callback

  (( ++ACTIONS_COUNTER ))
  >> "$ACTIONS_TAKEN_FILE" echo $modflag
  >> $UNDO_FILE echo "echo '### $modflag ###' "
  >> $UNDO_FILE echo "echo 'Restoring old iptables file...' "
  >> $UNDO_FILE echo "cp $modfilebak $modfile"
fi

ui_end_task "Step 1: Copy sample file"

ui_start_task "Step 2: Add iptables-init script"
script="configure_server.iptables-init.sh"
source <(
  ui_prompt_macro "Copy and install the iptables-init script?" proceed n
)
if [ "$proceed" != "y" ]; then
  ui_print_note "OK, no changes made."
else
  ui_print_note "Installing iptables-init.sh ..."

  "$LIB_DIR"/install_a_script.sh "$script" \
  | ui_escape_output "install_a_script"

  (( ++ACTIONS_COUNTER ))
  >> "$ACTIONS_TAKEN_FILE" echo "$modflag"

  >> $UNDO_FILE echo "echo '### $modflag ###' "
  >> $UNDO_FILE echo "echo 'Removing iptables-init.sh...' "
  >> $UNDO_FILE echo "rm `which iptables-init.sh` "
fi

# TODO: TEST
# BASED ON SECTION TEMPLATE 0.2
# - 
#   type: SECTION
#   testing:
#     - minimum
#     - undo
#     - force fix
# [A] Basic variables for this section
modflag="Setup fwsnort"
modfile=""
checkfile=""
# [B] Header
ui_section "$modflag"
# [C] check if we need to make our change
ui_print_note "Checking whether to make changes or not..."

if ls -d /var/lib/fwsnort; then
  ui_print_note "fwsnort is already installed."
  ui_print_note "No changes necessary."
else
  ui_print_note "fwsnort is not installed yet."
  # [D] ask whether to make changes
  source <(
    ui_prompt_macro "... Install fwsnort? [y/N]" proceed n
  )
  if [ "$proceed" != "y" ]; then
    ui_print_note "OK, no changes made."
  else
    ui_start_task "Installing fwsnort..."
    mkdir /opt && chcon --type="usr_t" /opt
    source <(
      "Which version of fwsnort to grab? [1.6.4]" proceed "1.6.4"
    )

    ui_print_note "Downloading http://cipherdyne.com/fwsnort/download/fwsnort-$fwsnort_version.tar.gz"
    wget http://cipherdyne.com/fwsnort/download/fwsnort-"$fwsnort_version".tar.gz -O /opt/fwsnort-"$fwsnort_version".tar.gz \
    | ui_escape_output "wget"
    cd /opt && tar xzf fwsnort-"$fwsnort_version".tar.gz
    ui_print_note "Installing perl and perl-CPAN ..."
    yum --assumeyes install gcc perl{,-CPAN} | sed 's/.*/[yum says] \0/'
    ui_start_task "Setting up dependencies for fwsnort"
    cd /opt/fwsnort-"$fwsnort_version"/deps \
    && for file in `ls -d | grep -v -e snort_rules -e whois`; do
      ui_start_task "Installing module $file"
      (cd $file && perl Makefile.PL && make && make install && cd ..) \
      | sed 's/.*/[installers] \0/'
      ui_end_task "Installing module $file"
    done
    ui_end_task "Setting up dependencies for fwsnort"

    # Finally, install fwsnort itself
    ui_print_note "... Please complete installation process for fwsnort ..."
    ui_press_any_key

    /opt/fwsnort-"$fwsnort_version"/install.pl

    ui_print_note "Installation completed"
    ui_press_any_key

    # [H] Stat the action
    (( ++ACTIONS_COUNTER ))

    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # [I] Append to undo file
    >> $UNDO_FILE echo "echo '### $modflag ###' "
    >> $UNDO_FILE echo "echo 'Uninstalling fwsnort...' "
    >> $UNDO_FILE echo "rm -rf /etc/fwsnort /var/lib/fwsnort '/opt/fwsnort-$fwsnort_version' "
    ui_print_note "Wrote undo file."
  fi
fi
# [K] ensure they acknowledge the above before proceeding
ui_press_any_key

# TODO: FINISH
####    echo "- Step 4: Customization"
####    echo "This file requires manual attention."
####    echo "Abort and fix file? [y/N]"
####    read proceed
####    if [[ $proceed == "y" ]]; then
####      exit 99 # aborted
####    else
####      echo "OK, no changes made."
####    fi

# NSA 2.5.7 Uncommon Network Protocols
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
ui_section "Uncommon Network Protocols"

modfile="/etc/modprobe.d/configure_server.exclusions.modprobe.conf"
modflag="configure_server directive 2.5.7"
if [ 0 '<' `grep "$modflag"$ "$modfile | wc -l` ]; then
  ui_print_note "Changes already made. Nothing to do."
else

  source <(
    ui_prompt_macro "Disable support for uncommon network protocols? [y/N]" proceed n
  )

  if [ "$proceed" != "y" ]; then
    ui_print_note "OK, no changes made."
  else

    source <(
      fn_backup_config_file_macro "$modfile" modfile_saveAfter_callback
    )

    cat <<END_FLAGS >> "$modfile"
# $modflag
install dccp /bin/true
# $modflag
install sctp /bin/true
# $modflag
install rds /bin/true
# $modflag
install tipc /bin/true
END_FLAGS

    modfile_saveAfter_callback

    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag

    # Append to undo file
    >> $UNDO_FILE echo "echo 'Removing uncommon network protocols disablement...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
    echo "Wrote undo file."

  fi
fi

# NSA 2.6.1.2.4 Confirm existence and Permissions of Log Files
# SECTION
# - TESTING:
#   - basic
#   - force fix
ui_section "Confirm existence and Permissions of Log Files"
ui_start_task "Step 1: Modfying /etc/rsyslog.conf"
echo "This must be done manually."
echo "Please hit ^Z and fix, then 'fg' when you are done to return to the process and press any key..."
read proceed
ui_end_task "Step 1: Modfying /etc/rsyslog.conf"

ui_start_task "Step 2: Check that log files exist"
modfile="/etc/rsyslog.conf"
modflag="configure_server directive 2.6.1.2.4"

# Accumulate list of files from rsyslog
cat "$modfile" \
| grep -v -e ^$ -e ^# -e ^\\$ \
| awk '{print $NF}' \
| grep -v -e "\\*" -e ^- \
  > "$SCRATCH"

if [ 0 == `cat "$SCRATCH" | wc -l` ]; then
  ui_print_note "No changes necessary."
else 
  ui_print_note "(NOTE: This action cannot be undone.)"
  source <(
    ui_prompt_macro "Interactively verify log files? [y/N/f]" proceed n
  )

  if [ "$proceed" != "y" ]; then
    echo "OK, no changes made."
  else
    for file in `cat "$SCRATCH"`; do
      if [ "$proceed" == "f"]; then
        # Forced to YES
        proceed="y"
      else
        source <(
          ui_prompt_macro "* Verify file '$file'? [y/N]" proceed2 n
        )
      fi

      if [ "$proceed2" != "y" ]; then
        ui_print_note "* OK, no changes made."
      else
	mkdir --parents ${file%/*}
        touch "$file"
	chown root:root "$file"
	chmod 0600 "$file"
      fi
    done

    modfile_saveAfter_callback

    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
  fi
fi

ui_end_task "Step 2: Check that log files exist"

# NSA 2.6.1.3 Logrotate
# SECTION
# - TESTING:
#   - basic
ui_section "Logrotate Configuration"

checkfile="/etc/rsyslog.conf"
modfile="/etc/logrotate.d/syslog"
modflag="configure_server directive 2.6.1.3"

ui_start_task "Step 1: Modfying $modfile"
echo "This must be done manually."
echo "Please hit ^Z and fix, then 'fg' when you are done to return to the process and press any key..."
read proceed
ui_end_task "Step 1: Modfying $modfile"

ui_start_task "Step 2: Verifying all rsyslog files are covered in logrotate"
# Get list of files, again
cat "$checkfile" \
| grep -v -e ^$ -e ^# -e ^\\$ \
| awk '{print $NF}' \
| grep -v -e "\\*" -e ^- \
  > "$SCRATCH"1

# Check whether each file is covered in logrotate
cat "$modfile" \
| grep --invert-match -e '^ ' -e "^	" \
| tr " \t" "\n\n" \
| grep --invert-match -e '{' -e '}' -e '^$' \
| sed 's/.*/^\0$/' \
  > "$SCRATCH"2

# Find difference
cat "$SCRATCH"1 \
| grep --invert-match --file="$SCRATCH"2 \
  > "$SCRATCH"

if [ -s $SCRATCH ]; then
  source <(
    fn_backup_config_file_macro "$modfile" modfile_saveAfter_callback
  )

  ui_print_note "Warning: Apparently the following syslog files are not rotated:"
  cat "$SCRATCH" | ui_print_list
  ui_print_note "Please hit ^Z, add them to '$modfile', and press any key when ready..."
  read proceed
  if [ "$modfile" -nt "$modfilebak" ]; then
    modfile_saveAfter_callback

    ui_print_note "Changes were saved."
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag

    >> $UNDO_FILE echo "echo 'Reverting changes to logrotate...' "
    >> $UNDO_FILE echo cp "$modfile.save-after_setup-`date +%F`" "$modfile"

    ui_print_note "Wrote to undo file."
  else
    ui_print_note "No changes detected."
  fi
else
  ui_print_note "No changes necessary."
fi

ui_end_task "Step 2: Verifying all rsyslog files are covered in logrotate"

# TODO
# CURRENTLY THE FOLLOWING IS HANDLED MANUALLY
# verify packages are uninstalled
## inetd xinetd telnet-server telnet krb5-workstation rsh-server rsh ypbind ypserv tftp-server talk-server talk isdn4k-utils kdump kudzu mdmonitor microcode_ctl irda-utils anacron bind
# yum list installed | awk '{print $1}' | grep --file="$DATA_DIR/uninstall_packages.txt" > "$SCRATCH"
#  cat $DATA_DIR/uninstall_packages.txt | tr "\n" " "| xargs yum --assumeyes remove
# - note: you will have to add cronie-noanacron
## grep --recursive pam_rhosts /etc/pam.d > "$SCRATCH" # should be null

# NSA 3.3.14.3 Disable Bluetooth Kernel Modules
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
ui_section "Bluetooth"

modfile="/etc/modprobe.d/configure_server.exclusions.modprobe.conf"
modflag="configure_server directive 3.3.14.3"

if [ 0 '<' `grep "$modflag"$ "$modfile | wc -l` ]; then
  ui_print_note "OK, nothing to do."
else
  source <(
    ui_prompt_macro "Disable bluetooth modules in kernel? [y/N]" proceed n
  )

  if [ "$proceed" != "y"]; then
    ui_print_note "OK, no action taken."
  else
    # Save old file
    source <(
      fn_backup_config_file_macro "$modfile" modfile_saveAfter_callback
    )

    >> $modfile echo "# $modflag"
    >> $modfile echo "alias net-pf-31 off"
    >> $modfile echo "# $modflag"
    >> $modfile echo "alias bluetooth off"

    modfile_saveAfter_callback

    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo "$modflag"

    # Append to undo file
    >> $UNDO_FILE echo "echo 'Removing bluetooth kernel disablement...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
    >> $UNDO_FILE echo "echo 'Changes will take effect after server restart.' "
    ui_print_note "Wrote undo file."
  fi
fi

# NSA 3.4.2 Restrict Permissions on Files Used by cron
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
ui_section "Restrict Permissions on Files Used by cron"

modfile=""
modflag="configure_server directive 3.4.2"

source <(
  ui_prompt_macro "Make permissions changes for cron files? (There is no undo) [y/N]"
)

if [ "$proceed" != "y" ]; then
  ui_print_note "Ok, skipping."
else
  ui_print_note "Ok, fixing permissions. (Note there may be errors from missing files or directories.)"
  chown root:root /etc/crontab
  chmod 600 /etc/crontab
  chown root:root /etc/anacrontab
  chmod 600 /etc/anacrontab
  chown -R root:root /etc/{cron.hourly,cron.daily,cron.weekly,cron.monthly,cron.d}
  chmod -R go-rwx /etc/{cron.hourly,cron.daily,cron.weekly,cron.monthly,cron.d}
  chown root:root /var/spool/cron
  chmod -R go-rwx /var/spool/cron

  (( ++ACTIONS_COUNTER ))
  >> "$ACTIONS_TAKEN_FILE" echo "$modflag"

fi

# NSA ??? Cron allow, deny
ui_section "Cron allow, deny"
echo "You must manually make any changes to cron.allow/deny. Press ^Z now if you wish, then hit enter when you come back."
echo "-- press any key to continue --"
read proceed


# NSA 3.5.2 SSHD Configuration
ui_section "Configure SSH Server"

modfile="/etc/ssh/sshd_config"
modflag="configure_server directive 3.5.2"

if [ 0 '<' `grep "$modflag"$ "$modfile | wc -l` ]; then
  ui_print_note "Changes already made. Nothing to do."
else
  source <(
    ui_prompt_macro "Add configuration to SSH server? [y/N]" proceed n
  )
  
  if [ "$proceed" != "y" ]; then
    ui_print_note "OK, no action taken."
  else
    source <(
      fn_backup_config_file_macro "$modfile" modfile_saveAfter_callback
    )

    >> "$modfile" cat <<END_FLAGS
# $modflag
Protocol 2
# $modflag
allowgroups humans
# $modflag
IgnoreRhosts yes
# $modflag
HostbasedAuthentication no
# $modflag
PermitRootLogin no
# $modflag
PermitEmptyPasswords no
# $modflag
PermitUserEnvironment no
END_FLAGS

    modfile_saveAfter_callback

    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag

    # Append to undo file
    >> $UNDO_FILE echo "echo 'Removing additions to SSH server...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
    ui_print_note "Wrote undo file."
  fi
fi

# NSA 3.6.1 Disable X Windows
ui_section "Disable X Windows RunLevel"
ui_start_task "Step 1: Check inittab runlevel"

modfile="/etc/inittab"
modflag="configure_server directive 3.6.1"

cat "$modfile" \
| awk --field-separator=":" '$2 != "3" && $3 == "initdefault" { print }' \
  > "$SCRATCH"

if [ -s $SCRATCH ]; then
  ui_print_note "WARNING: Wrong run level in /etc/inittab. Please ^Z and fix, then hit enter when you're back."
  echo "-- press any key to continue --"
  read proceed
else
  ui_print_note "Changes already made."
fi

ui_end_task "Step 1: Check inittab runlevel"

ui_start_task "Step 2: Remove all packages"
source <(
  ui_prompt_macro "Proceed to remove all X11 packages? [y/N]" proceed n
)

if [ "$proceed" != "y" ]; then
  echo "OK, no changes made."
else
  yum groupremove "X Windows System"
fi

# NSA 3.11.2.2 Conﬁgure Sendmail for Submission-Only Mode
ui_section "Configure Sendmail for Submission-Only Mode"

modfile="/etc/sysconfig/sendmail"
modflag="configure_server directive 3.11.2.2"
yum list installed \
| grep sendmail\\. \
  > "$SCRATCH"

if [ -s $SCRATCH ]; then
  ui_print_note "Application not installed. Nothing to do."
else
  # Check if changes have already been made.
  if [ 0 '<' `grep "$modflag"$ "$modfile | wc -l` ]; then
    ui_print_note "Changes already made. Nothing to do."
  else
    source <(
      ui_prompt_macro "Setup submission-only mode in sendmail? [y/N]" proceed n
    )

    if [ "$proceed" != "y" ]; then
      ui_print_note "OK, no changes made."
    else
      source <(
        fn_backup_config_file_macro "$modfile" modfile_saveAfter_callback
      )

      >> $modfile echo "# $modflag"
      >> $modfile echo "DAEMON=no"
      
      modfile_saveAfter_callback

      (( ++ACTIONS_COUNTER ))
      >> "$ACTIONS_TAKEN_FILE" echo $modflag

      # Append to undo file
      >> $UNDO_FILE echo "echo 'Removing additions to SSH server...' "
      >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
      ui_print_note "Wrote undo file."
    fi
  fi
fi

# NSA 3.15A VSFTP installation
ui_section "FTP configuration (vsftpd)"

modfile=""
modflag="configure_server directive 3.15A"
ui_print_note "Checking if vsftpd is installed..."
yum list installed \
| grep vsftpd\\. \
  > "$SCRATCH"

if [ ! -s $SCRATCH ]; then
  ui_print_note "vsftpd is installed."
else
  source <(
    ui_prompt_macro "vsftpd may not be installed. Install it? [y/N]" proceed n
  )

  if [ "$proceed" != "y" ]; then
    ui_print_note "OK, no changes made."
  else
    ui_print_note "OK, installing."

    yum --assumeyes install vsftpd \
    | ui_escape_output "yum"

    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag

    # Append to undo file
    >> $UNDO_FILE echo "echo 'Removing installation of vsftpd...' "
    >> $UNDO_FILE echo "yum --assumeyes remove vsftpd"
    ui_print_note "Wrote undo file."
  fi
fi

# TODO: Actually just append the sample file to the end of default configuration.
# # NSA 3.15B FTP Server Configuration
# modflag="configure_server directive 3.15B FTP Server"
# modfile="/etc/vsftpd/vsftpd.conf"
# >> $modfile echo 
# >> $modfile echo "# $modflag"
# >> $modfile echo "anonymous_enable=NO"
# >> $modfile echo "# $modflag"
# >> $modfile echo "log_ftp_protocol=YES"
# >> $modfile echo "# $modflag"
# >> $modfile echo "ftpd_banner=Greetings."
# >> $modfile echo "# $modflag"
# >> $modfile echo "chown_uploads=YES"
# >> $modfile echo "# $modflag"
# >> $modfile echo "chown_username=apache"
# >> $modfile echo "# $modflag"
# >> $modfile echo "local_enable=YES"
# >> $modfile echo "# $modflag"
# >> $modfile echo "chroot_local_user=YES"
# >> $modfile echo "# $modflag"
# >> $modfile echo "userlist_enable=YES"
# >> $modfile echo "# $modflag"
# >> $modfile echo "userlist_file=/etc/vsftpd/user_list"
# # TODO: ensure that right IP is used!
# >> $modfile echo "# $modflag"
# >> $modfile echo "pasv_address=54.84.7.7"
# >> $modfile echo "# $modflag"
# >> $modfile echo "pasv_min_port=49152"
# >> $modfile echo "# $modflag"
# >> $modfile echo "pasv_max_port=65534"
# >> $modfile echo "# $modflag"
# >> $modfile echo "port_enable=YES"
# >  /etc/vsftp/user_list # clear it out
# setsebool -P ftp_home_dir 1  # allow ftp users to change into their home directories
# setsebool -P allow_ftpd_full_access 1 # ONLY IF YOU CHROOT JAIL YOUR USERS. PLEASE TEST BEFORE ENABLING.
# TODO: Research if ftp_home_dir + chcon -t public_content_rw_t + allow_httpd_anon_write 
# # TODO: interactively add any users named "ftpSomething"
# >> $modfile echo "# $modflag"
# >> $modfile echo "userlist_deny=NO"
# >> /etc/sysconfig/iptables-config echo "# $modflag"
# >> /etc/sysconfig/iptables-config echo 'IPTABLES_MODULES="ip_conntrack_ftp"'
# Also: interactively add any existing ftp users
# REFERENCES:
# - https://access.redhat.com/site/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Managing_Confined_Services/sect-Managing_Confined_Services-File_Transfer_Protocol-Configuration_Examples.html

# POSTFIX 3.11.6
echo
echo "------------------------------"
echo "-- Email configuration (postfix)"
echo "------------------------------"
modfile=""
modflag="configure_server directive 3.11.6"
installpkg="postfix"
echo "Checking if $installpkg is installed..."
yum list installed \
| grep postfix\\. \
  > "$SCRATCH"
if [ ! -s $SCRATCH ]; then
  echo "$installpkg may not be installed. Install it? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    echo "OK, installing."
    yum --assumeyes install $installpkg
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Removing installation of $installpkg...' "
    >> $UNDO_FILE echo "yum --assumeyes remove $installpkg"
    echo "Wrote undo file."
  else
    echo "OK, no changes made."
  fi
else
  echo "$installpkg is already installed."
fi

# # POSTFIX 3.11.6
# modfile="/etc/postfix/main.cf"
# modflag="configure_server directive 3.11.6.1 Limit Service Attacks"
# >> $modfile echo "# $modflag"
# >> $modfile echo "default_process_limit = 100"
# >> $modfile echo "# $modflag"
# >> $modfile echo "smtpd_client_connection_count_limit = 10"
# >> $modfile echo "# $modflag"
# >> $modfile echo "smtpd_client_connection_rate_limit = 30"
# >> $modfile echo "# $modflag"
# >> $modfile echo "queue_minfree = 20971520140 CHAPTER 3. SERVICES"
# >> $modfile echo "# $modflag"
# >> $modfile echo "header_size_limit = 51200"
# >> $modfile echo "# $modflag"
# >> $modfile echo "message_size_limit = 10485760"
# >> $modfile echo "# $modflag"
# >> $modfile echo "smtpd_recipient_limit = 100"
# modfile=/etc/postfix/main.cf
# modflag="configure_server directive 3.11.6.2 Configure SMTP Greeting Banner"
# >> $modfile echo "# $modflag"
# >> $modfile echo "smtpd_banner = ESMTP"
# modfile=/etc/postfix/main.cf
# modflag="configure_server directive 3.11.6.3.1 Conﬁgure Trusted Networks and Hosts"
# >> $modfile echo "# $modflag"
# >> $modfile echo "mynetworks_style = host"
# modfile=/etc/postfix/main.cf
# modflag="configure_server directive 3.11.6.3.2 Allow Unlimited Relaying for Trusted Networks Only"
# echo "add permit_mynetworks, reject_unauth_destination, to smtpd_recipient_restrictions"
# # APACHE
# yum --assumeyes install httpd mod_ssl
# modfile="/etc/httpd/conf/httpd.conf"
# modflag="configure_server directive 3.16.3.1 Restrict Information Leakage"
# >> $modfile echo "# $modflag"
# >> $modfile echo "ServerTokens Prod"
# >> $modfile echo "# $modflag"
# >> $modfile echo " ServerSignature Off"
# # Apache may need this:
# setsebool -P httpd_can_network_connect 1
# * exclude the dav modules
# * exclude the status_module
# PHP
# yum --assumeyes install php{,-{common,devel,gd,mbstring,mysql,pdo,pear,soap,xmlrpc}}
# modfile="/etc/php.ini"
# modflag="configure_server directive 3.16.4.4.1"
# >> $modfile echo "; $modflag A Do not expose PHP error messages to external users"
# >> $modfile echo "display_errors = Off"
# >> $modfile echo "; $modflag B Enable safe mode"
# >> $modfile echo "safe_mode = On180 CHAPTER 3. SERVICES"
# >> $modfile echo "; $modflag C Only allow access to executables in isolated directory"
# >> $modfile echo "safe_mode_exec_dir = php-required-executables-path"
# >> $modfile echo "; $modflag D Limit external access to PHP environment"
# >> $modfile echo "safe_mode_allowed_env_vars = PHP_"
# >> $modfile echo "; $modflag E Restrict PHP information leakage"
# >> $modfile echo "expose_php = Off"
# >> $modfile echo "; $modflag F Log all errors"
# >> $modfile echo "log_errors = On"
# >> $modfile echo "; $modflag G Do not register globals for input data"
# >> $modfile echo "register_globals = Off"
# >> $modfile echo "; $modflag H Minimize allowable PHP post size"
# >> $modfile echo "post_max_size = 1K"
# >> $modfile echo "; $modflag I Ensure PHP redirects appropriately"
# >> $modfile echo "cgi.force_redirect = 0"
# >> $modfile echo "; $modflag J Disallow uploading unless necessary"
# >> $modfile echo "file_uploads = Off"
# >> $modfile echo "; $modflag K Disallow treatment of file requests as fopen calls"
# >> $modfile echo "allow_url_fopen = Off"
# >> $modfile echo "; $modflag L Enable SQL safe mode"
# >> $modfile echo "sql.safe_mode = On"
# # in php.ini, don't forget to specify timezone setting
# 
# # this must be run in the chroot for Apache, once HTTPD is setup
# chmod 511 /usr/sbin/httpd
# chmod 750 /var/log/httpd/
# chmod 750 /etc/httpd/conf/
# chmod 640 /etc/httpd/conf/*
# chgrp -R apache /etc/httpd/conf
# # make sure that /srv is httpd_sys_content_t
# # make sure that site dirs are httpd_sys_content_rw_t

# TODO: monitoring systems (fwsnort, psad, fail2ban, nagios)
# yum --assumeyes install gcc perl perl-CPAN
#*psad:
# cd /opt && wget http://cipherdyne.com/psad/download/psad-2.2.3.tar.gz
# tar xzf psad-*
# cd psad-*
# cd deps
# for dep in Bit-Vector Date-Calc NetAddr-IP Storable Unix-Syslog IPTables-Parse IPTables-ChainMgr; do
#   cd $dep && perl Makefile.PL && make && make install && cd ..
# done
# cd whois && make && make install && cd ..
# cd ..
# perl install.pl
# modflag="psad configuration: prevent pings from showing up"
# modfile="/etc/psad/auto_dl"
# >> $modfile echo "# $modflag"
# >> $modfile echo "# pings"
# >> $modfile echo "# $modflag"
# >> $modfile echo "184.106.158.119     0    icmp;"
# >> $modfile echo "# $modflag"
# >> $modfile echo "54.84.7.7           0    icmp;"
# >> $modfile echo "# $modflag"
# >> $modfile echo "71.19.154.48        0    icmp;"
# >> $modfile echo "# $modflag"
# >> $modfile echo "23.23.147.90        0    icmp;"

#*fwsnort:
# cd /opt && wget http://cipherdyne.com/fwsnort/download/fwsnort-1.6.4.tar.gz && tar xzf fwsnort-*tgz && cd fwsnort-*/ && perl install.pl
# fwsnort --update-rules && fwsnort && /var/lib/fwsnort/fwsnort.sh
#*finally:
# * make configuration changes to /etc/psad/psad.conf
# service psad start

# varnish:
# see https://www.varnish-cache.org/installation/redhat
# rpm --nosignature -i http://repo.varnish-cache.org/redhat/varnish-3.0/el6/noarch/varnish-release/varnish-release-3.0-1.el6.noarch.rpm
# yum install varnish
# # Adjust settings in varnish daemon opts
# modfile=/etc/sysconfig/varnish
# mv /etc/varnish/{,configure_server.}secret
# $ TODO: drive this with a file, varnish_settings.txt
# sed --in-place '/^VARNISH_VCL_CONF=/s/default.vcl$/configure_server.vcl/' "$modfile"
# sed --in-place '/^VARNISH_LISTEN_PORT=/s/[0-9]*$/80/' "$modfile"
# sed --in-place '/^VARNISH_SECRET_FILE=/s/secret$/configure_server.secret/' "$modfile"
# sed --in-place '/^VARNISH_STORAGE_SIZE=/s/=.*$/=3G/' "$modfile"
# sed --in-place '/^VARNISH_STORAGE=/s/=.*$/=malloc,${VARNISH_STORAGE_SIZE}/' "$modfile"
# cp samples/configure_server.vcl /etc/varnish

# mysql:
# yum --assumeyes install mysql{,-{common,libs,server}} php-mysql
# Remember to set root password:
# mysql> UPDATE mysql.user SET Password = PASSWORD(']Lm!s4u.2DK*&zsA>/Jh=bSS3') WHERE User='root';
# Also, clear out anonymous users:
# mysql> DELETE FROM mysql.user WHERE User='';
# mysql> FLUSH PRIVILEGES;

# users:
# -- ask about setting up rescue user
# -- ask about setting up current user, then run add_user.sh

# sysrq:
# -- ask whether to enable kernel.sysrq in sysctl.conf

# That's All Folks

echo "------------------------------"
echo "-- Conclusion"
echo "------------------------------"
echo "- Actions Taken: $ACTIONS_COUNTER "
echo "- Actions Log: Press any key..."
read proceed
cat "$ACTIONS_TAKEN_FILE" | nl | sed 's/.*/* \0/'
echo "- END OF ACTIONS TAKEN FILE"
echo
echo "Please see $UNDO_FILE for ability to revert most of the changes we have made."
echo "-- press any key to end --"
read proceed

exit 0
