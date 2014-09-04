#!/usr/bin/env bash

# USAGE:
#   $0 USER
# USER: Name of ftp user. Required.

# Get option: user
if [[ -n $1 ]]; then
  user="$1"
else
  # "I don't always die with an error, but when I do it's all caps."
  echo "FATAL ERROR: NO USERNAME SUPPLIED."
  exit 1
fi

# Use present directory by default
homedir="/home/$user"
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

echo "OK, user is $user"

humans_group="humans"
wheel_group="wheel"

# Setup runtime variables
source /var/lib/setup_script/setup_vars.sh \
|| (echo "Cannot find setup_vars.sh. Exiting..." && exit 3)

# Adding a user
echo "1. Create user itself, adding to humans and wheel groups"
echo "2. Add user's ssh key"
echo "3. Create mysql user for this one"

# Undo file
>  $UNDO_FILE echo "#!/bin/sh"
>> $UNDO_FILE echo

home_dir=/home/$user

echo ".. Creating user '$user' ..."

useradd --home-dir $home_dir -m --user-group --groups humans,wheel --shell /bin/bash $user \
|| (echo "ERROR: useradd failed with error #$? so exiting..." && exit 1) || exit 1

# Run our main command
useradd \
  --home $homedir \
  --create-home \
  --key UID_MIN=500 \
  --key UID_MAX=599 \
  --key UMASK=077 \
  --user-group \
  $user \
&& echo "... User created." \
|| (echo "... ERROR: Could not create user, #$?. Exiting..." && exit 1) || exit 1

# Grant ssh access (add to humans group)
echo "Add this user to humans? (This allows them to log into the server.)"
read proceed
if [[ $proceed != "y" ]]; then
  echo "Very well, did NOT add user to humans."
else
  echo "OK, adding user to humans..."
  gpasswd --add "$user" "$humans_group" \
  && echo "... User added to group: $humans_group" \
  || (echo "... ERROR: Could not add user to humans, #$?. Exiting..." && exit 1) || exit 1
  >> "$UNDO_FILE" echo "echo 'Removing user from humans...'"
  >> "$UNDO_FILE" echo "gpasswd --delete '$user' '$humans_group' "

  # Add their ssh key
  echo "(This is required for ssh login to work.)"
  echo "Please paste their ssh public key in 'ssh-rsa' format:"
  read pubkey

  l=mkdir $l --parents         $home_dir/.ssh \
  && l=echo  $l                >  $home_dir/.ssh/authorized_keys \
  && l=echo  $l $pubkey        >> $home_dir/.ssh/authorized_keys \
  && l=chown $l -R $user:$user $home_dir/.ssh \
  && l=chmod $l -R u+rw        $home_dir/.ssh \
  && l=chmod $l -R go-rwx      $home_dir/.ssh \
  || (echo "ERROR: Could not save public key. $l failed with error #$?." && exit 1) || exit 1

fi

# Grant sudo access (add to wheel group)
echo "Add this user to wheel? (This grants root sudo access.)"
read proceed
if [[ $proceed != "y" ]]; then
  echo "Very well, did NOT add user to wheel"
else
  echo "OK, adding user to wheel"
  gpasswd --add "$user" "$wheel_group" \
  && echo "... User added to group: $wheel_group" \
  || (echo "... ERROR: Could not add user to wheel, #$?. Exiting..." && exit 1) || exit 1
  >> "$UNDO_FILE" echo "echo 'Removing user from wheel'"
  >> "$UNDO_FILE" echo "gpasswd --delete '$user' '$wheel_group' "
fi

