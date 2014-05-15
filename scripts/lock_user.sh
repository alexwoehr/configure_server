#!/bin/sh

# Thoroughly lock a user

user=$1

if [[ -z $user ]]; then
  exit "ERRR: No user found. Exiting...."
  exit 1
fi

# Hide keys so they can't login
eval "cd ~"$user"/.ssh && mv authorized_keys unauthorized_keys"
# Remove them from sudoers and ssh enabled
gpasswd --delete $user humans
gpasswd --delete $user wheel

# Lock and disable login
usermod --lock --shell /sbin/nologin --homedir /chroot/nowhere $user

