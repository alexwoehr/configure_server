#!/bin/sh

# USAGE:
#   $0 USER [GROUP] [HOMEDIR]
# USER: Name of ftp user. Required.
# GROUP: Name of ftp group. E.g., ftpGroup_username, such as ftpTW_dfisher
# HOMEDIR: Path of home directory for this user

# Get option: user
if [[ -n $1 ]]; then
  user="$1"
else
  # "I don't always die with an error, but when I do it's all caps."
  echo "FATAL ERROR: NO USERNAME SUPPLIED."
  exit 1
fi

echo "OK, user is $user"

# Get option: group
if [[ -n $2 ]]; then
  group="$2"
else
  # Generate FTP from username supplied
  # Just take the part before the underscore, if an underscore was supplied
  group=${1%%_*}
  # Finally, confirm group name, if we are interactive.
  if [[ -z $NO_INTERACTIVE ]]; then
    echo "No group specified. Enter group. [$group]"
    read proceed
    if [[ -n $proceed ]]; then
      group="$proceed"
    fi
  fi
fi

echo "OK, ftp group is $group"

# Get option: home directory
if [[ -n $3 ]]; then
  homedir="$3"
else
  # Use present directory by default
  homedir=`pwd`
  if [[ -z $NO_INTERACTIVE ]]; then
    echo "No home directory specified. Enter directory. [$homedir]"
    read proceed
    if [[ -n $proceed ]]; then
      # They gave us a response
      homedir="$proceed"
    else
      : # use default homedirectory
    fi
  fi
fi

echo "OK, home is $homedir"

# Setup variables
source /var/lib/setup_script/setup_vars.sh \
|| (echo "Cannot find setup_vars.sh. Exiting..." && exit 3)

# Prevent creating home directory. It would be very unusual to create a new home directory for an FTP user.
OPT_DO_NOT_CREATE_HOME="-M" # no long option was available, sadly

# Undo file
>  $UNDO_FILE echo "#!/bin/sh"
>> $UNDO_FILE echo

# Add group if doesn't exist
echo "- Ensure group '$group' exists"
cut --delimiter=":" --fields=1 /etc/group \
| grep --fixed-strings --line-regexp "$group" \
  > "$SCRATCH"
if [[ -s $SCRATCH ]]; then
  echo "... Group found. No changes necessary."
else
  echo "... Creating group ..."

  groupadd \
    --key GID_MIN=600 \
    --key GID_MAX=699 \
    $group \
  && echo "... Group $group created." \
  || (echo "ERROR: Could not create group. #$?." && exit 1) || exit 1

  # Add to undo file
  >> $UNDO_FILE echo "echo 'Removing group $group...' "
  >> $UNDO_FILE echo "groupdel $group"
  echo "... Wrote undo file"

  # Add apache to new FTP group
  echo "... Adding apache to new group ..."
  usermod --append --groups $group apache
  echo "... Added apache."
  # Do not need to undo this action, as group does not exist, but doing it anyway, in case they pick and choose from the undo file
  >> $UNDO_FILE echo "echo 'Removing apache from group $group...' "
  >> $UNDO_FILE echo "gpasswd --delete apache $group"
  echo "... Wrote undo file"

fi

# Set remaining options for useradd command

base_dir=/chroot/nowhere 

echo ".. Creating user '$user' ..."

# Run our main command
useradd \
  --base-dir $base_dir \
  --home $homedir \
  $OPT_DO_NOT_CREATE_HOME \
  --key UID_MIN=600 \
  --key UID_MAX=699 \
  --key UMASK=077 \
  --user-group \
  --groups $group,allFTP \
  --shell /sbin/nologin \
  $user \
&& echo "... User created." \
|| (echo "... ERROR: Could not create user, #$?. Exiting..." && exit 1) || exit 1

# Add to undo file
>> $UNDO_FILE echo "echo 'Removing user $user...' "
>> $UNDO_FILE echo "userdel $user"
echo "... Wrote undo file"

# Add to FTP
echo ".. Adding FTP permission for user '$user' ..."
>> "/etc/vsftpd/user_list" echo $user
# Write undo
>> $UNDO_FILE echo "echo 'Revoking ftp privileges for $user...' "
>> $UNDO_FILE echo "sed -i '/^$user$/d' /etc/vsftpd/user_list"
echo "... Wrote undo file"

# Set password for user
echo "... Setting password for user"
echo "- Please press any key and then enter a password for the new FTP user."
read proceed
passwd $user \
&& echo "... Password was set" \
|| (usermod --lock $user && echo "... WARNING: Locked user because we could not set password.  You can unlock them with usermod --unlock $user." && exit 1) || exit 1

