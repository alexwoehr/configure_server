#!/usr/bin/env bash

CHROOT_NAME="$1"
shift
CHROOT_CMD="$*"

CHROOT_JAIL_DIR="/chroot/$CHROOT_NAME"

# Do not quote chroot_cmd so it splits up into words
chroot --userspec="chroot_$CHROOT_NAME" \
       "$CHROOT_JAIL_DIR" \
       $CHROOT_CMD

