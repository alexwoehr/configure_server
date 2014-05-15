#!/bin/sh

echo 
echo "=============================="
echo "== WELCOME TO SECURITY HARDENING SCRIPT"
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

# SECTION
# - TESTING:
#   - basic
#   - basic centos
#   - basic debian
##########################
# SELinux and other prerequisites
##########################
echo "------------------------------"
echo "-- Setup SELinux"
echo "------------------------------"
sestatus
sestatus | grep "disabled" > "$SCRATCH"
if [ -s "$SCRATCH" ]; then
  echo "Please setup SELINUX on your own."
  echo "Quit script? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    exit 99; # aborted
  fi
else
  echo "No changes necessary."
fi

echo "------------------------------"
echo "-- Runtime Global Variables"
echo "------------------------------"
modflag="configure_server create standard directories"
echo "Create our standard directories? [y/N]"
read proceed
if [[ $proceed == "y" ]]; then
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
echo
echo "------------------------------"
echo "-- Remove Extra FS Types"
echo "------------------------------"
modfile="/etc/modprobe.d/configure_server.exclusions.modprobe.conf"
modflag="configure_server directive 2.2.1"
cat "$modfile" \
| grep "$modflag"$ \
  > "$SCRATCH"
if [ ! -s $SCRATCH ]; then
  echo "Proceed? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    # Save old file
    modfilebak="$modfile".save-before_setup-`date +%F`
    if [ ! -e "$modfilebak" ]; then
      cp $modfile $modfilebak
    fi
    for fs in usb-storage {cram,freevx,h,squash}fs jffs2 hfsplus udf; do
      >> "$modfile" echo "# $modflag"
      >> "$modfile" echo "install $fs /bin/true"
    done
    cp $modfile $modfile.save-after_setup-`date +%F`
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Undoing FS disables...' "
    >> $UNDO_FILE echo "sed --in-place '/^# $modflag/,+1d' '$modfile'"
    echo "Wrote to undo file."
  else
    echo "OK, did not proceed."
  fi
else
  echo "Already done. No action taken."
fi

# NSA 2.2.2 Permissions
# NSA 2.2.2.1
# SECTION
# - TESTING:
#   - basic
echo
echo "------------------------------"
echo "-- Password Permissions"
echo "------------------------------"
echo "proceeding because no sane individual would refuse. Only sane individuals are allowed to run this script."
chown root:root /etc/{passwd,shadow,group,gshadow}
chmod 644 /etc/{passwd,group}
chmod 400 /etc/{shadow,gshadow}

# NSA 2.2.2.2 World Writable Directories
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
echo
echo "------------------------------"
echo "-- Fix World Writable Directories"
echo "------------------------------"
modfile=""
modflag="configure_server directive 2.2.2.2"
results_file="$TMP_DIR/NSA.2.2.2.2.world_writable_dirs.txt"
> $results_file
for PART in $PARTITIONS; do
  find $PART -xdev -type d \( -perm -0002 -a ! -perm -1000 \) -print
done >> $results_file

# Interactive part
if [[ ! -s $results_file ]]; then
  echo "No results."
else
  for dir in `cat $results_file`; do
    echo "Set sticky bit for $dir? [y/N]"
    read proceed
    if [[ $proceed == "y" ]]; then
      echo "Performing operation..."
      chmod +t "$dir"
      (( ++ACTIONS_COUNTER ))
      >> "$ACTIONS_TAKEN_FILE" echo $modflag
      # Append to undo file
      >> $UNDO_FILE echo "echo 'Undoing sticky bit set on $dir...' "
      >> $UNDO_FILE echo "chmod -t '$dir'"
      echo "Wrote to undo file."
    else
      echo "OK, no action taken"
    fi
  done
fi

# NSA 2.2.2.3 World Writable Files
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
echo
echo "------------------------------"
echo "-- Fix World Writable Files"
echo "------------------------------"
modfile=""
modflag="configure_server directive 2.2.2.3A"
results_file="$TMP_DIR/NSA.2.2.2.3.world_writable_files.txt"
> $results_file
for PART in $PARTITIONS; do
  find $PART -xdev -type f \( -perm -0002 -a ! -perm -1000 \) -print
done >> $results_file

# Interactive part
if [[ ! -s $results_file ]]; then
  echo "No results."
else
  for file in $(< $results_file); do
    echo "Clear world writable permissions on $file? [y/N]"
    read proceed
    if [[ $proceed == "y" ]]; then
      echo "Performing operation..."
      chmod o-w "$file"
      (( ++ACTIONS_COUNTER ))
      >> "$ACTIONS_TAKEN_FILE" echo $modflag
      # Append to undo file
      >> $UNDO_FILE echo "echo 'Undoing world writable reset for $file...' "
      >> $UNDO_FILE echo "chmod o+w '$file'"
      echo "Wrote to undo file."
    else
      echo "OK, no action taken"
    fi
  done
fi

# NSA 2.2.2.3 SUID / SGID permissions
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
echo
echo "------------------------------"
echo "-- Fix SUID Executables"
echo "------------------------------"
modfile=""
modflag="configure_server directive 2.2.2.3A"
results_file="$TMP_DIR/NSA.2.2.2.4.suid.txt"
> $results_file
for PART in $PARTITIONS; do
  find $PART -xdev \( -perm -4000 \) -type f -print
done | grep --invert-match --file="$DATA_DIR/suid_files_allow.txt" >> $results_file
# Do not test /chroot jails
sed --in-place "/^\\/chroot\\//d" "$results_file"

# Interactive part
if [[ ! -s $results_file ]]; then
  echo "No results."
else
  for file in `cat "$results_file"`; do
    echo "Clear setuid on $file? [y/N]"
    read proceed
    if [[ $proceed == "y" ]]; then
      echo "Performing operation..."
      chmod u-s "$file"
      (( ++ACTIONS_COUNTER ))
      >> "$ACTIONS_TAKEN_FILE" echo $modflag
      # Append to undo file
      >> $UNDO_FILE echo "echo 'Undoing suid removal on $file...' "
      >> $UNDO_FILE echo "chmod u+s '$file'"
      echo "Wrote to undo file."
    else
      echo "Skipped $file."
    fi
  done
fi

# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
echo
echo "------------------------------"
echo "-- Fix SGID Executables"
echo "------------------------------"
modflag="configure_server directive 2.2.2.3B"
results_file="$TMP_DIR/NSA.2.2.2.4.sgid.txt"
> $results_file
for PART in $PARTITIONS; do
  find $PART -xdev \( -perm -2000 \) -type f -print
done | grep --invert-match --file="$DATA_DIR/suid_files_allow.txt" >> $results_file

# Do not test /chroot jails
sed --in-place "/^\\/chroot\\//d" "$results_file"

# Interactive part
if [[ ! -s $results_file ]]; then
  echo "No results."
else
  for file in `cat "$results_file"`; do
    echo "Clear setgid on $file? [y/N]"
    read proceed
    if [[ $proceed == "y" ]]; then
      echo "Performing operation..."
      chmod g-s "$file"
      (( ++ACTIONS_COUNTER ))
      >> "$ACTIONS_TAKEN_FILE" echo $modflag
      # Append to undo file
      >> $UNDO_FILE echo "echo 'Undoing suid removal on $file...' "
      >> $UNDO_FILE echo "chmod g+s '$file'"
      echo "Wrote to undo file."
    else
      echo "Skipped $file."
    fi
  done
fi

# NSA 2.2.4 Dangerous Execution Patterns
# NSA 2.2.4.1 umask
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
echo
echo "------------------------------"
echo "-- umask"
echo "------------------------------"
# Check if operation has been performed yet
modfile="/etc/sysconfig/init"
modflag="configure_server directive 2.2.4.1"
cat "$modfile" \
| grep "$modflag"$ \
| tee $SCRATCH \
&& if [ ! -s $SCRATCH ]; then
  echo "Add umask? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    # Save old file
    modfilebak="$modfile".save-before_setup-`date +%F`
    if [ ! -e "$modfilebak" ]; then
      cp $modfile $modfilebak
    fi
    echo "Setting umask sanely to 027.."
    >> $modfile echo "# $modflag"
    >> $modfile echo "umask 027"
    # Save new file
    cp $modfile $modfile.save-after_setup-`date +%F`
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Undoing umask set...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
  else
    echo "OK, not changed."
  fi
else
  echo "Already done. No action taken."
fi

# NSA 2.2.4.2 Disable Core Dumps
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
echo
echo "------------------------------"
echo "-- Disable Core Dumps"
echo "------------------------------"
modfile="/etc/security/limits.conf"
modflag="configure_server directive 2.2.4.2A"
cat "$modfile" \
| grep "$modflag"$ \
| tee $SCRATCH \
&& if [ ! -s $SCRATCH ]; then
  echo "Disable core dumps in $modfile? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    # Save old file
    modfilebak="$modfile".save-before_setup-`date +%F`
    if [ ! -e "$modfilebak" ]; then
      cp $modfile $modfilebak
    fi
    echo "Performing operation on $modfile..."
    >> $modfile echo "# $modflag"
    >> $modfile echo "*        hard core 0"
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Save new file
    cp $modfile $modfile.save-after_setup-`date +%F`
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Undoing core dump disablement on limits.conf...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
    echo "Wrote to undo file."
  else
    echo "OK, no action taken"
  fi
else
  echo "Already done. No action taken."
fi

modfile="/etc/sysctl.conf"
modflag="configure_server directive 2.2.4.2B"
cat "$modfile" \
| grep "$modflag"$ \
| tee $SCRATCH \
&& if [ ! -s $SCRATCH ]; then
  echo "Disable core dumps in $modfile? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    # Save old file
    modfilebak="$modfile".save-before_setup-`date +%F`
    if [ ! -e "$modfilebak" ]; then
      cp $modfile $modfilebak
    fi
    echo "Performing operation on $modfile..."
    >> $modfile echo "# $modflag"
    >> $modfile echo "fs.suid_dumpable = 0"
    # Save new file
    cp $modfile $modfile.save-after_setup-`date +%F`
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Undoing core dump disablement on $modfile...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
    echo "Wrote to undo file."
  else
    echo "OK, no action taken"
  fi
else
  echo "Already done. No action taken."
fi

# NSA 2.2.4.3 execshield
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
echo
echo "------------------------------"
echo "-- ExecShield"
echo "------------------------------"
modfile="/etc/sysctl.conf"
modflag="configure_server directive 2.2.4.3"
cat "$modfile" \
| grep "$modflag"$ \
| tee $SCRATCH \
&& if [ ! -s $SCRATCH ]; then
  echo "Enable exec-shield? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    # Save old file
    modfilebak="$modfile".save-before_setup-`date +%F`
    if [ ! -e "$modfilebak" ]; then
      cp $modfile $modfilebak
    fi
    echo "Enabling ExecShield.."
    >> $modfile echo "# $modflag"
    >> $modfile echo "kernel.exec-shield = 1" 
    >> $modfile echo "# $modflag"
    >> $modfile echo "kernel.randomize_va_space = 1"
    # Save new file
    cp $modfile $modfile.save-after_setup-`date +%F`
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Undoing exec-shield enable...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
  else
    echo "Not changed."
  fi
else
  echo "Already done. No action taken."
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
echo
echo "------------------------------"
echo "-- Restrict Root Logins to System Console "
echo "------------------------------"
checkfile="/etc/securetty"
modflag="configure_server directive 2.3.1.1"
checks=`cat $DATA_DIR/securetty_allowed.txt | tr "\n" "|" | sed 's/|/ -e /g' | sed 's/-e $//'`
cat "$checkfile" \
| eval "grep --invert-match -E -e $checks " \
  > "$SCRATCH"
if [ -s $SCRATCH ]; then 
  echo "The following extraneous consoles have been discovered:"
  sed 's/.*/- \0/' $SCRATCH
  echo
  echo "Remove these items? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    # Create new file with only accepted consoles
    cat $checkfile \
    | eval "grep -E -e $checks " \
      > "$SCRATCH"new
    mv "$SCRATCH"new $checkfile
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo   "echo 'Re-adding removed consoles...' "
    for console in `cat $SCRATCH`; do
      >> $UNDO_FILE echo ">> '$checkfile' echo '$console'"
    done
  else
    echo "OK, no changes made."
  fi
else
  echo "No changes necessary."
fi


# NSA 2.3.1.2 Limit su Access to the Root Account
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
echo
echo "------------------------------"
echo "-- Limit su Access to the Root Account"
echo "------------------------------"
checkfile="/etc/group"
modfile=""
modflag="configure_server directive 2.3.1.2A"
wheelgroup=wheel
echo "- Step 1. Create wheel group."
grep "^$wheelgroup:" "$checkfile" \
  > $SCRATCH
if [ ! -s $SCRATCH ]; then 
  echo "There is no $wheelgroup group. Create it? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    groupadd "$wheelgroup"
    echo "WARNING: Please add $wheelgroup restriction to pam!"
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

# BASED ON SECTION TEMPLATE 0.2
# - 
#   type: SECTION
#   testing:
#     - minimum
#     - undo
#     - force fix
# [A] Basic variables for this section
modflag="configure_server directive 2.3.1.2B"
modfile="/etc/pam.d/su"
# [B] Header
echo "---------------------"
echo "- $modflag: Add wheel permissions to pam"
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
  echo "... Restriction sudoing to wheel group in pam? [y/N]"
  read proceed
  if [[ $proceed != "y" ]]; then
    echo "... OK, no changes made."
  else
    # [E] backup modfile before making changes
    modfilebak="$modfile".save-before_setup-`date +%F`
    if [[ ! -e "$modfilebak" ]]; then
      cp $modfile $modfilebak
    fi
    echo "... Changing $modfile ..."
    >> $modfile echo "# $modflag"
    >> $modfile echo "security=1"

    while true; do
      # Check if they have signed off on changes yet.
      grep "# CHANGES OK" $modfile
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

    echo "... Done."
    # [H] Stat the action
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag "interactively for $file"
    # [I] Append to undo file
    >> $UNDO_FILE echo "echo '### $modflag ###' "
    >> $UNDO_FILE echo "echo 'Removing changes to $modfile...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
    echo "... Wrote undo file."
    # [J] now backup current versions
    cp $modfile $modfile.save-after_setup-`date +%F`
  fi
fi
# [K] ensure they acknowledge the above before proceeding
echo "-- press enter when ready --"
read proceed

# NSA 2.3.1.3 Conﬁgure sudo to Improve Auditing of Root Access
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
echo
echo "------------------------------"
echo "-- Limit sudo privileges for only $wheelgroup"
echo "------------------------------"
modfile="/etc/sudoers"
modflag="configure_server directive 2.3.1.3"
cat $modfile \
| grep "$modflag"$ \
  > $SCRATCH
if [ ! -s $SCRATCH ]; then 
  echo "Add sudoers enablement for su? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    # Save old file
    modfilebak="$modfile".save-before_setup-`date +%F`
    if [ ! -e "$modfilebak" ]; then
      cp $modfile $modfilebak
    fi
    >> $modfile echo "# $modflag"
    >> $modfile echo '%wheel ALL=(ALL) NOPASSWD: ALL'
    # Save new file
    cp $modfile $modfile.save-after_setup-`date +%F`
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Removing wheel group sudoers enablement...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
    echo "Wrote to undo file."
  else
    echo "OK, no changes made."
  fi
else
  echo "No changes necessary."
fi

# NSA 2.3.1.4 Block Shell and Login Access for Non-Root System Accounts
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
echo
echo "------------------------------"
echo "-- Block Shell and Login Access for Non-Root System Accounts"
echo "------------------------------"
modfile="/etc/passwd"
modflag="configure_server directive 2.3.1.4"
# List accounts that should definitely be locked
# First step: find nonhuman users (less than 500) and ftp users (greater than 100)
cat $modfile \
| grep --invert-match root \
| awk --field-separator=":" '$3 < 500 || substr($1, 1, 3) == "ftp" { print "^" $1 ":" }'  \
  > "$SCRATCH"1
# Second step: exclude those with "nologin"
cat $modfile \
| grep --file="$SCRATCH"1 \
| awk --field-separator=":" '$NF != "/sbin/nologin" && $1 != substr($NF, length($NF) - length($1) + 1) { print $1 }' \
  > "$SCRATCH"2
# Third step: exclude those with locked password -- preceded by "!"
cat /etc/shadow \
| grep --file="$SCRATCH"1 \
| awk --field-separator=":" 'substr($2, 1, 1) != "!" { print $1 }' \
  > "$SCRATCH"3
if [ -s "$SCRATCH"2 -o -s "$SCRATCH"3 ]; then 
  echo "Lock and block login to following accounts?"
  cat "$SCRATCH"{2,3} | tr "\n" "\t"
  echo
  echo "Interactively lock these non-human users and block access? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    modfilebak="$modfile".save-before_setup-`date +%F`
    if [ ! -e "$modfilebak" ]; then
      cp $modfile $modfilebak
    fi
    echo "* BEGIN INTERACTIVE LOCK AND BLOCK *"
    for acct in `cat "$SCRATCH"2`; do
      echo "* Block access to account '$acct'? [y/N]"
      read proceed
      if [[ $proceed == "y" ]]; then
	echo "* Blocking access to '$acct'."
        usermod --shell /sbin/nologin $acct
        >> $UNDO_FILE echo "usermod --shell" `cat "$modfilebak" | grep "^$acct:" | awk --field-separator=":" '{ print $NF }'` "$acct"
	echo "Wrote to undo file."
      else
        echo "OK, no action taken."
      fi
    done
    for acct in `cat "$SCRATCH"3`; do
      echo "* Lock password to account '$acct'? [y/N]"
      read proceed
      if [[ $proceed == "y" ]]; then
	echo "* Locked password for '$acct'."
        usermod --lock $acct
        >> $UNDO_FILE echo "usermod --unlock '$acct'"
	echo "Wrote to undo file."
      else
        echo "OK, no action taken."
      fi
    done
    echo "* END OF INTERACTIVE LOCK AND BLOCK *"
    # Save new file
    cp $modfile $modfile.save-after_setup-`date +%F`
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
  else
    echo "OK, no changes made."
  fi
else
  echo "No changes necessary."
fi

# NSA 2.3.1.5 Verify Proper Storage and Existence of Password Hashes
# SECTION
# - TESTING:
#   - basic
echo
echo "------------------------------"
echo "-- Verify Proper Storage and Existence of Password Hashes"
echo "------------------------------"
echo "- Step 1: Ensure no empty passwords"
echo "-         [seems impossible, but might as well check]"
checkfile="/etc/shadow"
modflag="configure_server directive 2.3.1.5A"
# List accounts that should definitely be locked
cat $checkfile \
| awk --field-separator=":" '($2 == "") {print $1}' \
  > $SCRATCH
if [ -s $SCRATCH ]; then 
  echo "Passwords are empty for following accounts:"
  cat $SCRATCH | tr "\n" "\t"
  echo
  echo "Reenter passwords for these users? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    cat $SCRATCH | xargs --max-args=1 --delimiter="\n" passwd
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Following users had empty passwords, not reverting...' "
    cat $SCRATCH | tr "\n" "\t"
    echo "Wrote undo file (with no-op)."
  else
    echo "OK, no changes made."
  fi
else
  echo "No changes necessary."
fi

# SECTION
# - TESTING:
#   - basic
echo "- Step 2: Ensure no passwords in passwd file"
echo "-         [untested b/c highly unlikely]"
checkfile="/etc/passwd"
modflag="configure_server directive 2.3.1.5B"
# List accounts that should definitely be locked
cat $checkfile \
| awk --field-separator=":" '($2 != "x") {print $1}' \
  > $SCRATCH
if [ -s $SCRATCH ]; then 
  echo "Invalid passwords for following files were discovered:"
  cat $SCRATCH | tr "\n" "\t"
  echo \n
  echo "Reenter passwords for these users? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    cat $SCRATCH | xargs --max-args=1 --delimiter="\n" passwd
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Following users had passwords in wrong place. Passwords were changed...' "
    tr "\n" "\t" $SCRATCH
    echo "Wrote undo file (with no-op)."
    echo "NOTE: you should test whether this worked because it has not been tested."
    echo "Please hit ^Z and fix, then 'fg' when you are done to return to the process and press any key..."
    read proceed
  else
    echo "OK, no changes made."
  fi
else
  echo "No changes necessary."
fi

# NSA 2.3.1.6 Verify that No Non-Root Accounts Have UID 0
# SECTION
# - TESTING:
#   - basic
echo
echo "------------------------------"
echo "-- Verify that No Non-Root Accounts Have UID 0"
echo "------------------------------"
echo "- [untested because it is a very unlikely scenario]"
checkfile="/etc/passwd"
modflag="configure_server directive 2.3.1.6"
cat $checkfile \
| awk --field-separator=":" '$3 == "0" && $1 != "root" {print}' \
  > $SCRATCH
if [ -s $SCRATCH ]; then 
  echo "Following nonroot 0 UID users were discovered. Swift removal is recommended."
  cat $SCRATCH | tr "\n" "\t"
  echo "Please hit ^Z and fix, then 'fg' when you are done to return to the process and press any key..."
  read proceed
  ###   read proceed
  ###   if [[ $proceed == "y" ]]; then
  ###     cat $SCRATCH | xargs --max-args=1 --delimiter="\n" passwd
  ###     (( ++ACTIONS_COUNTER ))
  ###     >> "$ACTIONS_TAKEN_FILE" echo $modflag
  ###     # Append to undo file
  ###     >> $UNDO_FILE echo "echo 'Following users had passwords in wrong place. Passwords were changed...' "
  ###     tr "\n" "\t" $SCRATCH
  ###     echo "Wrote undo file (with no-op)."
  ###   else
  ###     echo "OK, no changes made."
  ###   fi
else
  echo "No changes necessary."
fi

# NSA 2.3.1.7 Set Password Expiration Date Parameters
# not implementing...

# NSA 2.3.1.8 Remove Legacy + Entries from Password Files
# SECTION
# - TESTING:
#   - basic
echo
echo "------------------------------"
echo "-- Remove Legacy + Entries from Password Files"
echo "------------------------------"
echo "- [untested because it is a very unlikely scenario]"
checkfiles=`echo /etc/{passwd,shadow,group}`
modflag="configure_server directive 2.3.1.8"
eval "grep '^+:' $checkfiles" \
  > $SCRATCH
if [ -s $SCRATCH ]; then 
  echo "Following users with legacy '+' password were discovered. See $modflag NSA policy. Please address very soon."
  cat $SCRATCH | tr "\n" "\t"
  echo "Please hit ^Z and fix, then 'fg' when you are done to return to the process and press any key..."
  read proceed
  ###   read proceed
  ###   if [[ $proceed == "y" ]]; then
  ###     cat $SCRATCH | xargs --max-args=1 --delimiter="\n" passwd
  ###     (( ++ACTIONS_COUNTER ))
  ###     # Append to undo file
  ###     >> $UNDO_FILE echo "echo 'Following users had passwords in wrong place. Passwords were changed...' "
  ###     tr "\n" "\t" $SCRATCH
  ###     echo "Wrote undo file (with no-op)."
  ###   else
  ###     echo "OK, no changes made."
  ###   fi
else
  echo "No changes necessary."
fi

# NSA 2.3.2.2 Create and Maintain a Group Containing All Human Users
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
echo
echo "------------------------------"
echo "-- Create and Maintain a Group Containing All Human Users"
echo "------------------------------"
checkfile="/etc/group"
modfile=""
modflag="configure_server directive 2.3.2.2A"
humansgroup=humans
echo "- Step 1. Create humans group."
grep "^humans:" "$checkfile" \
  > $SCRATCH
if [ ! -s $SCRATCH ]; then 
  echo "There is no '$humansgroup' group. Create it? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    groupadd "$humansgroup"
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Removing added '$humansgroup' group...' "
    >> $UNDO_FILE echo "groupdel '$humansgroup'"
    echo "Wrote undo file."
  else
    echo "OK, no changes made."
  fi
else
  echo "No changes necessary."
fi

echo "- Step 2. Add users to humans group."
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
checkfile="/etc/passwd"
modfile=""
modflag="configure_server directive 2.3.2.2B"
grep "^humans:" /etc/group \
  > "$SCRATCH"
if [ -s $SCRATCH ]; then 
  # Get list of users that are already in humans
  # Create grepfile for existing humans
  grep '^humans:' /etc/group \
  | cut --delimiter=':' --fields="4-" \
  | tr "," "\n" \
  | sed 's/.*/^\0:/' \
    > "$SCRATCH"1

  cat $checkfile \
  | grep --invert-match --file="$SCRATCH"1 \
  | awk --field-separator=":" 'substr($1, 1, 4) == "root" || ($3 > 500 && substr($1, 1, 3) != "ftp") { print $1 }'  \
    > $SCRATCH

  if [ -s $SCRATCH ]; then 
    echo "These possibly human users were found. Interactively confirm to add them?"
    cat $SCRATCH | tr "\n" "\t"
    echo
    echo "Proceed to interactive addition of users? [y/N]"
    read proceed
    if [[ $proceed == "y" ]]; then
      for maybehuman in `cat "$SCRATCH"`; do
        echo "* Add '$maybehuman' to '$humansgroup'? [y/N]"
        read proceed
        if [[ $proceed == "y" ]]; then
          echo "* Added '$maybehuman'"
          usermod --append --groups "$humansgroup" "$maybehuman"
          (( ++ACTIONS_COUNTER ))
          >> "$ACTIONS_TAKEN_FILE" echo $modflag
          # Append to undo file
          >> $UNDO_FILE echo "echo \"Removing '$maybehuman' from '$humansgroup'...\" "
          >> $UNDO_FILE echo "gpasswd --delete '$maybehuman' '$humansgroup'"
          echo "Wrote to undo file."
        else
          echo "* OK, '$maybehuman' was not added.";
        fi
      done;
    else
      echo "OK, not adding humans at this point."
    fi
  else
    echo "No changes necessary."
  fi
else
  echo "No changes necessary because you did not select to create a '$humansgroup' group."
fi

# STATUS: ignoring pam changes for now
####    # NSA 2.3.3.1 Set Password Quality Requirements
####    echo
####    echo "------------------------------"
####    echo "-- Set Password Quality Requirements"
####    echo "------------------------------"
####    modfile="/etc/pam.d/system-auth"
####    modflag="configure_server directive 2.3.3.1"
####    cat $modfile \
####    | grep "$modflag"$ \
####    | tee $SCRATCH \
####    && if [ ! -s $SCRATCH ]; then 
####      # TODO: check if passwordqc already specified
####      echo "Add password quality upgrade to pam? [y/N]"
####      read proceed
####      if [[ $proceed == "y" ]]; then
####        # Save old file
####        modfilebak="$modfile".save-before_setup-`date +%F`
####        if [ ! -e "$modfilebak" ]; then
####          cp $modfile $modfilebak
####        fi
####        >> $modfile echo "# $modflag";
####        >> $modfile echo "password required pam_cracklib.so try_first_pass retry=3 minlen=14 dcredit=-1 ucredit=-1 ocredit=-1 lcredit=-1"
####        # Save new file
####        cp $modfile $modfile.save-after_setup-`date +%F`
####        (( ++ACTIONS_COUNTER ))
####        >> "$ACTIONS_TAKEN_FILE" echo $modflag
####        # Append to undo file
####        >> $UNDO_FILE echo "echo 'Removing password quality requirements...' "
####        >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
####        echo "Wrote to undo file."
####      else
####        echo "OK, no changes made."
####      fi
####    else
####      echo "No changes necessary."
####    fi

echo "NOTE: please complete all PAM configuration manually!"
echo "Press Enter to continue..."
read proceed
echo "OK, no changes made."

# NSA 2.3.4.1 Ensure that No Dangerous Directories Exist in Root's Path
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
echo
echo "------------------------------"
echo "-- Ensure that No Dangerous Directories Exist in Root's Path"
echo "------------------------------"
echo "Please modify your bash file to edit the path, if desired."
echo "Press Enter to continue..."
read proceed
echo "OK, no changes made."

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
echo
echo "------------------------------"
echo "--  Implement Inactivity Time-out for Login Shells"
echo "------------------------------"
modfile="/etc/profile.d/tmout.sh"
modflag="configure_server directive 2.3.5.5"
if [ ! -e "$modfile" ]; then 
  echo "Inactivity timeout file is not created. Create it? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    >  $modfile
    >> $modfile echo "#!/bin/sh"
    >> $modfile echo "# $modflag"
    >> $modfile echo "TMOUT=36000"
    >> $modfile echo "# $modflag"
    >> $modfile echo "readonly TMOUT"
    >> $modfile echo "# $modflag"
    >> $modfile echo "export TMOUT"
    chown root:root "$modfile"
    chmod u+rwx "$modfile"
    echo "Created '$modfile'. Contents:"
    cat "$modfile" | sed 's/.*/* \0/'
    # Save new file
    cp $modfile $modfile.save-after_setup-`date +%F`
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo "$modflag"
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Removing inactivity timeout for login shells file...' "
    >> $UNDO_FILE echo "rm '$modfile'"
  else
    echo "OK, no changes made."
  fi
else
  echo "File already exists."
  echo "No changes necessary."
fi

# NSA 2.3.5.6-7 skipped
# NSA 2.3.6 skipped

# NSA 2.3.7.1 Warning Banners for System Accesses
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
echo
echo "------------------------------"
echo "--  Warning Banners for System Accesses"
echo "------------------------------"
echo "- Two files to check: issue and issue.net"
if [ -n `ls /etc/issue{,.net} | tr "\n" ','` ]; then
  for modfile in /etc/issue{,.net}; do
    modflag="configure_server directive 2.3.6"
    if [ -s "$modfile" ]; then 
      echo "Login banner '$modfile' has info. Remove it? [y/N]"
      read proceed
      if [[ $proceed == "y" ]]; then
        # Save old file
        modfilebak="$modfile".save-before_setup-`date +%F`
        if [ ! -e "$modfilebak" ]; then
          cp "$modfile" "$modfilebak"
        fi
        # Truncate it
        >  $modfile
        cp $modfile $modfile.save-after_setup-`date +%F`
        (( ++ACTIONS_COUNTER ))
        >> "$ACTIONS_TAKEN_FILE" echo "$modflag"
        # Append to undo file
        >> $UNDO_FILE echo "echo \"Re-adding the banner '$modfile'...\" "
        >> $UNDO_FILE echo "cp '$modfilebak' '$modfile'"
      else
        echo "OK, no changes made."
      fi
    else
      echo "No changes necessary for $modfile."
    fi
  done
else
  echo "No banners files found."
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
echo
echo "------------------------------"
echo "-- Kernel Parameters which Affect Networking: Network Parameters for Hosts Only"
echo "------------------------------"
modfile="/etc/sysctl.conf"
modflag="configure_server directive 2.5.1.1"
grep "$modflag" "$modfile" \
  > $SCRATCH
if [ ! -s $SCRATCH ]; then 
  echo "We have not yet changed forwarding in '$modfile'. Change it? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    # Save old file
    modfilebak="$modfile".save-before_setup-`date +%F`
    if [ ! -e "$modfilebak" ]; then
      cp "$modfile" "$modfilebak"
    fi
    >> "$modfile" echo "# $modflag"
    >> "$modfile" echo "net.ipv4.ip forward = 0"
    >> "$modfile" echo "# $modflag"
    >> "$modfile" echo "net.ipv4.conf.all.send redirects = 0"
    >> "$modfile" echo "# $modflag"
    >> "$modfile" echo "net.ipv4.conf.default.send redirects = 0"
    echo "OK, $modfile changed."
    # Save new file
    cp $modfile $modfile.save-after_setup-`date +%F`
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Removing forwarding prevention rules...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
  else
    echo "OK, no changes made."
  fi
else
  echo "No changes necessary."
fi

# NSA 2.5.1.2 Kernel Parameters which Affect Networking: Network Parameters for Hosts and Routers
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
echo
echo "------------------------------"
echo "-- Kernel Parameters which Affect Networking: Network Parameters for Hosts and Routers"
echo "------------------------------"
modfile="/etc/sysctl.conf"
modflag="configure_server directive 2.5.1.2"
grep "$modflag" "$modfile" \
  > $SCRATCH
if [ ! -s $SCRATCH ]; then 
  echo "We have not yet added log_martians to '$modfile'. Change it? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    # Save old file
    modfilebak="$modfile".save-before_setup-`date +%F`
    if [ ! -e "$modfilebak" ]; then
      cp $modfile $modfilebak
    fi
    >> "$modfile" echo "# $modflag"
    >> "$modfile" echo "net.ipv4.conf.all.log_martians = 1"
    >> "$modfile" echo "# $modflag"
    >> "$modfile" echo "net.ipv4.conf.all.accept_source_route = 0"
    >> "$modfile" echo "# $modflag"
    >> "$modfile" echo "net.ipv4.conf.all.accept_redirects = 0"
    >> "$modfile" echo "# $modflag"
    >> "$modfile" echo "net.ipv4.conf.all.secure_redirects = 0"
    >> "$modfile" echo "# $modflag"
    >> "$modfile" echo "net.ipv4.conf.all.log_martians = 1"
    >> "$modfile" echo "# $modflag"
    >> "$modfile" echo "net.ipv4.conf.default.accept_source_route = 0"
    >> "$modfile" echo "# $modflag"
    >> "$modfile" echo "net.ipv4.conf.default.accept_redirects = 0"
    >> "$modfile" echo "# $modflag"
    >> "$modfile" echo "net.ipv4.conf.default.secure_redirects = 0"
    >> "$modfile" echo "# $modflag"
    >> "$modfile" echo "net.ipv4.icmp_echo_ignore_broadcasts = 1"
    >> "$modfile" echo "# $modflag"
    >> "$modfile" echo "net.ipv4.icmp_ignore_bogus_error_messages = 1"
    >> "$modfile" echo "# $modflag"
    >> "$modfile" echo "net.ipv4.tcp_syncookies = 1"
    >> "$modfile" echo "# $modflag"
    >> "$modfile" echo "net.ipv4.conf.all.rp_filter = 1"
    >> "$modfile" echo "# $modflag"
    >> "$modfile" echo "net.ipv4.conf.default.rp_filter = 1"
    # Save new file
    cp $modfile $modfile.save-after_setup-`date +%F`
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Removing log_martians...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
  else
    echo "OK, no changes made."
  fi
else
  echo "No changes necessary."
fi

# NSA 2.5.1.3 Ensure System is Not Acting as a Network Sniffer
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
echo
echo "------------------------------"
echo "-- Ensure System is Not Acting as a Network Sniffer"
echo "------------------------------"
checkfile="/proc/net/packet"
modfile=""
modflag="configure_server directive 2.5.1.2"
cat /proc/net/packet | wc -l > "$SCRATCH"
if [ 1 -lt `cat "$SCRATCH"` ]; then 
  echo "Here is the packet file. There are " `cat "$SCRATCH"` " lines in the file."
  cat /proc/net/packet | nl | sed 's/.*/* \0/'
  echo "Abort and investigate? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    exit 99 # aborted
  else
    echo "OK, no changes made."
  fi
else
  echo "No changes necessary."
fi

# NSA 2.5.4 skipped

# NSA 2.5.5 iptables
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
echo
echo "------------------------------"
echo "-- IPTABLES"
echo "------------------------------"
modfile=/etc/sysconfig/iptables
modflag="configure_server directive 2.5.5A iptables"
echo "- Step 1: Copy sample file"
echo "Copy the iptables sample to the config directory? [y/N]"
read proceed
if [[ $proceed == "y" ]]; then
  # Save old file
  modfilebak="$modfile".save-before_setup-`date +%F`
  if [ ! -e "$modfilebak" ]; then
    cp $modfile $modfilebak
  fi
  cp $LIB_DIR/samples/iptables /etc/sysconfig/iptables
  cp $modfile $modfile.save-after_setup-`date +%F`
  (( ++ACTIONS_COUNTER ))
  >> "$ACTIONS_TAKEN_FILE" echo $modflag
  >> $UNDO_FILE echo "echo '### $modflag ###' "
  >> $UNDO_FILE echo "echo 'Restoring old iptables file...' "
  >> $UNDO_FILE echo "cp $modfilebak $modfile"
else
  echo "OK, no changes made."
fi
echo "- Step 2: Add iptables-init script"
script="configure_server.iptables-init.sh"
echo "Copy and install the iptables-init script?"
read proceed
if [[ $proceed == "y" ]]; then
  echo "... Installing ..."
  $LIB_DIR/install_a_script.sh $script \
  | sed 's/.*/[installing script] \0/'
  (( ++ACTIONS_COUNTER ))
  >> "$ACTIONS_TAKEN_FILE" echo $modflag
  >> $UNDO_FILE echo "echo '### $modflag ###' "
  >> $UNDO_FILE echo "echo 'Restoring old iptables file...' "
  >> $UNDO_FILE echo "cp $modfilebak $modfile"
else
  echo "OK, no changes made."
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
echo "---------------------"
echo "- $modflag"
echo "---------------------"
# [C] check if we need to make our change
echo "... Checking whether to make changes or not..."

if ls -d /var/lib/fwsnort; then
  echo "... fwsnort is already installed."
  echo "... No changes necessary."
else
  echo "... fwsnort is not installed yet."
  # [D] ask whether to make changes
  echo "... Install fwsnort? [y/N]"
  read proceed
  if [[ $proceed != "y" ]]; then
    echo "... OK, no changes made."
  else
    mkdir /opt && chcon --type="usr_t"
    echo "... Which version of fwsnort to grab? [1.6.4]"
    read proceed
    if [[ -z $proceed ]]; then
      fwsnort_version="1.6.4"
    else
      fwsnort_version=$proceed
    fi
    echo "... Downloading http://cipherdyne.com/fwsnort/download/fwsnort-$fwsnort_version.tar.gz"
    wget http://cipherdyne.com/fwsnort/download/fwsnort-$fwsnort_version.tar.gz -O /opt/fwsnort-$fwsnort_version.tar.gz | sed 's/.*/[wget says] \0/'
    cd /opt && tar xzf fwsnort-$fwsnort_version.tar.gz
    echo "... Installing perl and perl-CPAN ..."
    yum --assumeyes install gcc perl{,-CPAN} | sed 's/.*/[yum says] \0/'
    echo "... Setting up dependencies for fwsnort ..."
    cd /opt/fwsnort-$fwsnort_version/deps \
    && for file in `ls -d | grep -v -e snort_rules -e whois`; do
      echo "... Installing module $file ..."
      (cd $file && perl Makefile.PL && make && make install && cd ..) \
      | sed 's/.*/[installers] \0/'
      echo "... Done installing module $file ..."
    done
    # Finally, install fwsnort itself
    echo "... Please complete installation process for fwsnort ..."
    echo "-- press enter when ready --"
    read proceed
    /opt/fwsnort-$fwsnort_version/install.pl
    echo "... Installation completed ..."
    echo "-- press enter when ready --"
    read proceed
    # [H] Stat the action
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # [I] Append to undo file
    >> $UNDO_FILE echo "echo '### $modflag ###' "
    >> $UNDO_FILE echo "echo 'Uninstalling fwsnort...' "
    >> $UNDO_FILE echo "rm -rf /etc/fwsnort /var/lib/fwsnort '/opt/fwsnort-$fwsnort_version' "
    echo "... Wrote undo file."
  fi
fi
# [K] ensure they acknowledge the above before proceeding
echo "-- press enter when ready --"
read proceed
# End of Section Template

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
echo
echo "------------------------------"
echo "-- Uncommon Network Protocols"
echo "------------------------------"
modfile="/etc/modprobe.d/configure_server.exclusions.modprobe.conf"
modflag="configure_server directive 2.5.7"
cat "$modfile" \
| grep "$modflag$" \
  > "$SCRATCH"
if [ ! -s $SCRATCH ]; then 
  echo "Disable support for uncommon network protocols? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    # Save old file
    modfilebak="$modfile".save-before_setup-`date +%F`
    if [ ! -e "$modfilebak" ]; then
      cp $modfile $modfilebak
    fi
    >> "$modfile" echo "# $modflag"
    >> "$modfile" echo "install dccp /bin/true"
    >> "$modfile" echo "# $modflag"
    >> "$modfile" echo "install sctp /bin/true"
    >> "$modfile" echo "# $modflag"
    >> "$modfile" echo "install rds /bin/true"
    >> "$modfile" echo "# $modflag"
    >> "$modfile" echo "install tipc /bin/true"
    # Save new file
    cp $modfile $modfile.save-after_setup-`date +%F`
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Removing uncommon network protocols disablement...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
  else
    echo "OK, no changes made."
  fi
else
  echo "Changes already made."
fi

# NSA 2.6.1.2.4 Confirm existence and Permissions of Log Files
# SECTION
# - TESTING:
#   - basic
#   - force fix
echo
echo "------------------------------"
echo "-- Confirm existence and Permissions of Log Files"
echo "------------------------------"
echo "- Step 1: Modfying /etc/rsyslog.conf"
echo "This must be done manually."
echo "Please hit ^Z and fix, then 'fg' when you are done to return to the process and press any key..."
read proceed
echo "- Step 2: Check that log files exist"
modfile="/etc/rsyslog.conf"
modflag="configure_server directive 2.6.1.2.4"
cat "$modfile" \
| grep -v -e ^$ -e ^# -e ^\\$ \
| awk '{print $NF}' \
| grep -v -e "\\*" -e ^- \
  > "$SCRATCH"
if [ -s $SCRATCH ]; then 
  echo "(NOTE: This action cannot be undone.)"
  echo "Interactively verify log files? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    for file in `cat "$SCRATCH"`; do
      echo "* Verify file '$file'?"
      read proceed
      if [[ $proceed == "y" ]]; then
	mkdir --parents ${file%/*}
        touch "$file"
	chown root:root "$file"
	chmod 0600 "$file"
      else
        echo "* OK, no changes made."
      fi
    done
    cp $modfile $modfile.save-after_setup-`date +%F`
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
  else
    echo "OK, no changes made."
  fi
else
  echo "No changes necessary."
fi

# NSA 2.6.1.3 Logrotate
# SECTION
# - TESTING:
#   - basic
echo
echo "------------------------------"
echo "-- Logrotate Configuration"
echo "------------------------------"
checkfile="/etc/rsyslog.conf"
modfile="/etc/logrotate.d/syslog"
modflag="configure_server directive 2.6.1.3"
echo "- Step 1: Modfying $modfile"
echo "This must be done manually."
echo "Please hit ^Z and fix, then 'fg' when you are done to return to the process and press any key..."
read proceed
echo "- Step 2: Verifying all rsyslog files are covered in logrotate"
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
  modfilebak="$modfile".save-before_setup-`date +%F`
  if [ ! -e "$modfilebak" ]; then
    cp $modfile $modfilebak
  fi
  echo "Warning: Apparently the following syslog files are not rotated:"
  cat "$SCRATCH" | sed 's/.*/* \0/'
  echo
  echo "Please hit ^Z, add them to '$modfile', and press any key when ready..."
  read proceed
  if [ $modfile -nt $modfilebak ]; then
    # Save new file
    cp $modfile $modfile.save-after_setup-`date +%F`
    echo "Changes were saved."
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    >> $UNDO_FILE echo "echo 'Reverting changes to logrotate...' "
    >> $UNDO_FILE echo cp "$modfile.save-after_setup-`date +%F`" "$modfile"
    echo "Wrote to undo file."
  else
    echo "No changes detected."
  fi
else
  echo "No changes necessary."
fi

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
echo
echo "------------------------------"
echo "-- Bluetooth"
echo "------------------------------"
modfile="/etc/modprobe.d/configure_server.exclusions.modprobe.conf"
modflag="configure_server directive 3.3.14.3"
cat "$modfile" \
| grep "$modflag$" \
  > "$SCRATCH"
if [ ! -s $SCRATCH ]; then 
  echo "Disable bluetooth modules in kernel? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    # Save old file
    modfilebak="$modfile".save-before_setup-`date +%F`
    if [ ! -e "$modfilebak" ]; then
      cp $modfile $modfilebak
    fi
    >> $modfile echo "# $modflag"
    >> $modfile echo "alias net-pf-31 off"
    >> $modfile echo "# $modflag"
    >> $modfile echo "alias bluetooth off"
    # Save new file
    cp $modfile $modfile.save-after_setup-`date +%F`
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Removing bluetooth kernel disablement...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
    >> $UNDO_FILE echo "echo 'Changes will take effect after server restart.' "
  else
    echo "OK, no changes made."
  fi
else
  echo "Changes already made."
fi

# NSA 3.4.2 Restrict Permissions on Files Used by cron
# SECTION
# - TESTING:
#   - basic
#   - force fix
#   - undo
echo
echo "------------------------------"
echo "--  Restrict Permissions on Files Used by cron"
echo "------------------------------"
modfile=""
modflag="configure_server directive 3.4.2"
echo "Make permissions changes for cron files? (There is no undo) [y/N]"
read proceed
if [[ $proceed == "y" ]]; then
  echo "Ok, fixing permissions. (Note there may be errors from missing files or directories.)"
  chown root:root /etc/crontab
  chmod 600 /etc/crontab
  chown root:root /etc/anacrontab
  chmod 600 /etc/anacrontab
  chown -R root:root /etc/{cron.hourly,cron.daily,cron.weekly,cron.monthly,cron.d}
  chmod -R go-rwx /etc/{cron.hourly,cron.daily,cron.weekly,cron.monthly,cron.d}
  chown root:root /var/spool/cron
  chmod -R go-rwx /var/spool/cron
  (( ++ACTIONS_COUNTER ))
  >> "$ACTIONS_TAKEN_FILE" echo $modflag
else
  echo "OK, no changes made."
fi

# NSA ??? Cron allow, deny
echo
echo "------------------------------"
echo "--  Cron allow, deny"
echo "------------------------------"
echo "You must manually make any changes to cron.allow/deny. Press ^Z now if you wish, then hit enter when you come back."
echo "-- press any key to continue --"
read proceed


# NSA 3.5.2 SSHD Configuration
echo
echo "------------------------------"
echo "-- Configure SSH Server"
echo "------------------------------"
modfile="/etc/ssh/sshd_config"
modflag="configure_server directive 3.5.2"
cat "$modfile" \
| grep "$modflag$" \
  > "$SCRATCH"
if [ ! -s $SCRATCH ]; then 
  echo "Add configuration to SSH server? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    # Save old file
    modfilebak="$modfile".save-before_setup-`date +%F`
    if [ ! -e "$modfilebak" ]; then
      cp $modfile $modfilebak
    fi
    >> $modfile echo "# $modflag"
    >> $modfile echo "Protocol 2"
    >> $modfile echo "# $modflag"
    >> $modfile echo "allowgroups humans"
    >> $modfile echo "# $modflag"
    >> $modfile echo "IgnoreRhosts yes"
    >> $modfile echo "# $modflag"
    >> $modfile echo "HostbasedAuthentication no"
    >> $modfile echo "# $modflag"
    >> $modfile echo "PermitRootLogin no"
    >> $modfile echo "# $modflag"
    >> $modfile echo "PermitEmptyPasswords no"
    >> $modfile echo "# $modflag"
    >> $modfile echo "PermitUserEnvironment no"
    # Save new file
    cp $modfile $modfile.save-after_setup-`date +%F`
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Removing additions to SSH server...' "
    >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
  else
    echo "OK, no changes made."
  fi
else
  echo "Changes already made."
fi

# NSA 3.6.1 Disable X Windows
echo
echo "------------------------------"
echo "-- Disable X Windows RunLevel"
echo "------------------------------"
echo "- Step 1: Check inittab runlevel"
modfile="/etc/inittab"
modflag="configure_server directive 3.6.1"
cat "$modfile" \
| awk --field-separator=":" '$2 != "3" && $3 == "initdefault" { print }' \
  > "$SCRATCH"
if [ -s $SCRATCH ]; then 
  echo "WARNING: Wrong run level in /etc/inittab. Please ^Z and fix, then hit enter when you're back."
  echo "-- press any key to continue --"
  read proceed
else
  echo "Changes already made."
fi

echo "- Step 2: Remove all packages"
echo "Proceed to remove all X11 packages? [y/N]"
read proceed
if [[ $proceed == "y" ]]; then
  yum groupremove "X Windows System"
else
  echo "OK, no changes made."
fi

# NSA 3.11.2.2 Conﬁgure Sendmail for Submission-Only Mode
echo
echo "------------------------------"
echo "-- Configure Sendmail for Submission-Only Mode"
echo "------------------------------"
modfile="/etc/sysconfig/sendmail"
modflag="configure_server directive 3.11.2.2"
yum list installed \
| grep sendmail\\. \
  > "$SCRATCH"
if [ -s $SCRATCH ]; then
  # Check if changes have already been made.
  cat "$modfile" \
  | grep "$modflag$" \
    > "$SCRATCH"
  if [ ! -s $SCRATCH ]; then 
    echo "Setup submission-only mode in sendmail? [y/N]"
    read proceed
    if [[ $proceed == "y" ]]; then
      # Save old file
      modfilebak="$modfile".save-before_setup-`date +%F`
      if [ ! -e "$modfilebak" ]; then
        cp $modfile $modfilebak
      fi
      >> $modfile echo "# $modflag"
      >> $modfile echo "DAEMON=no"
      # Save new file
      cp $modfile $modfile.save-after_setup-`date +%F`
      (( ++ACTIONS_COUNTER ))
      >> "$ACTIONS_TAKEN_FILE" echo $modflag
      # Append to undo file
      >> $UNDO_FILE echo "echo 'Removing additions to SSH server...' "
      >> $UNDO_FILE echo "sed --in-place '/$modflag$/,+1d' '$modfile'"
    else
      echo "OK, no changes made."
    fi
  else
    echo "Changes already made."
  fi
else
  echo "sendmail is not installed, nothing to do."
fi

# NSA 3.15A VSFTP installation
echo
echo "------------------------------"
echo "-- FTP configuration (vsftpd)"
echo "------------------------------"
modfile=""
modflag="configure_server directive 3.15A"
echo "Checking if vsftpd is installed..."
yum list installed \
| grep vsftpd\\. \
  > "$SCRATCH"
if [ ! -s $SCRATCH ]; then
  echo "vsftpd may not be installed. Install it? [y/N]"
  read proceed
  if [[ $proceed == "y" ]]; then
    echo "OK, installing."
    yum --assumeyes install vsftpd
    (( ++ACTIONS_COUNTER ))
    >> "$ACTIONS_TAKEN_FILE" echo $modflag
    # Append to undo file
    >> $UNDO_FILE echo "echo 'Removing installation of vsftpd...' "
    >> $UNDO_FILE echo "yum --assumeyes remove vsftpd"
    echo "Wrote undo file."
  else
    echo "OK, no changes made."
  fi
else
  echo "vsftpd is installed."
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
