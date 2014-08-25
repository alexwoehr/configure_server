#!/usr/bin/env bash

# References: see this file:
# - https://github.com/amedeos/UVarnishChroot/blob/master/varnish-chroot.sh

# Load libraries
source ./ui.inc
source ./functions.inc

# Setup variables
source ./setup_vars.sh \
  || (echo "Cannot find setup_vars.sh. Exiting..." && exit 3)

readonly CHROOT_NAME="varnish"
readonly CHROOT_JAIL_DIR=/chroot/"$CHROOT_NAME"
readonly CHROOT_LOOP_FILE=/chroot/Loops/"$CHROOT_NAME".loop

readonly USER=varnish
readonly CHROOT_USER=chroot_"$USER"

# Build varnish jail with default parameters
cd "$LIB_DIR"
yes | ./build_chroot_jail.sh "$CHROOT_NAME"

# install packages for varnish
chroot "$CHROOT_JAIL" <<END_COMMANDS
  rpm --nosignature -i https://repo.varnish-cache.org/redhat/varnish-4.0.el6.rpm

  yum --assumeyes install varnish \
  | ui_escape_output "yum"
END_COMMANDS

# Copy over sample conf files
if [[ -e "$LIB_DIR"/samples/"$CHROOT_NAME".defaults ]]; then
  cp -v "$LIB_DIR"/samples/"$CHROOT_NAME".defaults "$CHROOT_JAIL_DIR"/etc/sysconfig/varnish
fi

if [[ -e "$LIB_DIR"/samples/"$CHROOT_NAME".default.vcl ]]; then
  cp -v "$LIB_DIR"/samples/"$CHROOT_NAME".default.vcl "$CHROOT_JAIL_DIR"/etc/varnish/default.vcl
fi

# Step down privileges and initiate the chrooted daemon
cd $CHROOT_JAIL_DIR \
&& chroot "${CHROOT_JAIL_DIR}" su "$CHROOT_USER" /sbin/service varnish start

# TODO: Create options for--
# - do not create dev (? does varnish need dev and proc?)
# - do not copy executables
# - setup daemon things automatically

