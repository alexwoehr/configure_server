#!/usr/bin/env bash

# Load libraries
source ./ui.inc
source ./functions.inc

# Setup variables
source ./setup_vars.sh \
  || (echo "Cannot find setup_vars.sh. Exiting..." && exit 3)

readonly CHROOT_NAME="mysql"
readonly CHROOT_JAIL_DIR=/chroot/"$CHROOT_NAME"
readonly CHROOT_LOOP_FILE=/chroot/Loops/"$CHROOT_NAME".loop

readonly USER="$CHROOT_NAME"
readonly CHROOT_USER=chroot_"$USER"

# Build mysql jail with default parameters
pushd "$LIB_DIR" \
&& yes | ./build_chroot_jail.sh "$CHROOT_NAME"
popd

# mysqld expects to find this
cp {,/chroot/mysql}/etc/sysconfig/network

# install packages for varnish
chroot "$CHROOT_JAIL_DIR" <<END_COMMANDS | ui_escape_output "yum"
  yum --assumeyes install mysql55{,-{devel,libs,server}} \
END_COMMANDS

# Copy over sample conf files
if [[ -e "$LIB_DIR"/samples/"$CHROOT_NAME".defaults ]]; then
  cp -v "$LIB_DIR"/samples/"$CHROOT_NAME".defaults "$CHROOT_JAIL_DIR"/etc/sysconfig/"$CHROOT_NAME"
fi

if [[ -e "$LIB_DIR"/samples/"$CHROOT_NAME".cnf ]]; then
  cp -v "$LIB_DIR"/samples/"$CHROOT_NAME".cnf "$CHROOT_JAIL_DIR"/etc/
fi

mkdir --parents var/run/"$CHROOT_NAME"

# Create contained data files (in mysql owned directory) and update my.cnf to use them
chroot . <<"END_CMDS"
  for dir in lib log run; do
    sed --in-place 's/var\/'\$dir'/\0\/mysql-container/' /etc/my.cnf
    mkdir --parents /var/\$dir/_mysql-container
    mv /var/\$dir/{mysql*,_mysql-container/}
    mv /var/\$dir/{_,}mysql-container
    chown -R mysql:mysql /var/\$dir/mysql-container
  done

  # Lock file
  mkdir --parents /var/lock/subsys/mysql-container
  touch /var/lock/subsys/mysql-container/mysqld
  chown -R mysql:mysql /var/lock/subsys/mysql-container
END_CMDS

# Change lock file in init script to use different file
change_line=$(grep --line-number --fixed-strings --line-regexp -e 'lockfile=/var/lock/subsys/$prog' /etc/init.d/mysqld | cut -d: -f1 )
readonly new_value='lockfile=/var/lock/subsys/mysql-container/mysqld'
sed --in-place "${change_line}c\\\n$new_value" etc/init.d/mysqld

# Step down privileges and initiate mysql daemon
cd "$CHROOT_JAIL_DIR" \
&& chroot --userspec="$USER" "$CHROOT_JAIL_DIR" /sbin/service mysqld start

# TODO: Create options for--
# - do not create dev (mysql does not need dev and proc)
# - do not copy executables
# - setup daemon things automatically

