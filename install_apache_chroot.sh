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

USER=varnish

# Build default chroot jail
yes | build_chroot_jail.sh "$CHROOT_NAME"

# Custom 3Fold stuff
# mount xvde5 (srv) within the apache chroot
umount /dev/xvde5 \
&& rm -rf --one-file-system "$CHROOT_JAIL"/srv/* \
&& mount -o defaults,nodev,nosuid /dev/xvde5 "$CHROOT_JAIL"/srv

# link some crucial things from the main server into the chroot. (you can jump in but you can't jump out)
rm -rf --one-file-system /srv
ln -s "$CHROOT_JAIL"/srv /srv # link srv root
rm -rf --one-files-system /etc/httpd
ln -s "$CHROOT_JAIL"/etc/httpd/ /srv # link httpd configuration root

# Install packages.
yum --assumeyes install httpd php-mysql php-pear php-xml php-mysql php-cli php-imap php-gd php-pdo php-devel php-mbstring php-common php-ldap php httpd-devel

