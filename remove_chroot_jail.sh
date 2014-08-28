#!/usr/bin/env bash

# TODO:
# * make it more interactive

# Load libraries
source ./ui.inc
source ./functions.inc

# Setup variables
source ./setup_vars.sh \
  || (echo "Cannot find setup_vars.sh. Exiting..." && exit 3)

if [[ -z $1 ]]; then
  ui_print_note "You must supply the name of the new chroot to create."
  ui_print_note "Exiting.."
  exit 2
fi

readonly CHROOT_NAME="$1"
readonly CHROOT_JAIL_DIR=/chroot/"$CHROOT_NAME"
readonly CHROOT_LOOP_FILE=/chroot/Loops/"$CHROOT_NAME".loop

source <(
  ui_prompt_macro "You are deleting the entire file system in '$CHROOT_JAIL_DIR'. Proceed? [y/N]" proceed n
)

if [[ $proceed != "y" ]]; then
  ui_print_note "OK. Aborting..."
  exit 99
fi

# Unmount touchy inner parts
inner_mounts="/proc /dev"
if [[ $1 == "apache" ]]; then
  inner_mounts="$inner_mounts /srv"
fi

for inner_mount in $INNER_MOUNTS; do
  if umount "$CHROOT_JAIL_DIR""$INNER_MOUNTS"; then
    ui_print_note "Unmounted $INNER_MOUNT successfully."
  else 
    ui_print_note "Could not unmount $INNER_MOUNT. Aborting..."
    exit 99
  fi
done

# Delete each fstab reference to the chroot
# This is done in ***REVERSE ORDER*** (that's super important) because otherwise the line numbers change.
fstab_lines="$(grep --line-number --fixed-strings "$CHROOT_JAIL_DIR" /etc/fstab | cut -d: -f1 | tac)"
for line in $fstab_lines; do
  sed --in-place "${line}"d /etc/fstab
done

if [[ -e "$CHROOT_LOOP_FILE" ]]; then
  umount "$CHROOT_JAIL_DIR"
  rm --force "$CHROOT_LOOP_FILE"
else
  rm -rf --one-file-system "$CHROOT_JAIL_DIR"
fi

