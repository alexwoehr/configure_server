#!/usr/bin/env bash

# Load libraries
source ./ui.inc
source ./functions.inc

# Setup variables
source ./setup_vars.sh \
  || (echo "Cannot find setup_vars.sh. Exiting..." && exit 3)


readonly pkg_base_download="http://mirror.centos.org/centos/6/os/x86_64/Packages/centos-release-6-5.el6.centos.11.1.x86_64.rpm"

if [[ -n $1 ]]; then
  ui_print_note "You must supply the name of the new chroot to create."
  ui_print_note "Exiting.."
  exit 2
fi
readonly JAIL_DIR=/chroot/"$1"

ui_start_task "Create chroot jail directory"

mkdir --parents "$JAIL_DIR"/var/lib/rpm

ui_end_task "Create chroot jail directory"

ui_start_task "Setup rpm base"

rpm --rebuilddb --root="$JAIL_DIR"

# Subshell
(
  cd "$TMP_DIR"
  wget "$pkg_base_download"
  rpm -i --root=/var/tmp/chroot --nodeps "${pkg_base_download##*/}"
)

ui_end_task "Setup rpm base"

ui_start_task "Install all core packages"

yum --installroot="$JAIL_DIR" install --assumeyes rpm-build yum \
  | ui_escape_output "yum"

ui_end_task "Install all core packages"

ui_start_task "Setup remaining inner directories"

cp "$JAIL_DIR"{/etc/skel/.??*,/root

mount --bind /proc /var/tmp/chroot/proc
mount --bind /dev /var/tmp/chroot/dev

cp {,"$JAIL_DIR"}/etc/resolv.conf

ui_end_task "Setup remaining inner directories"


ui_print_note "Setup is finished."
ui_print_note "Now you should be able to chroot into the new system and complete any remaining setup by using the following command:"

chroot "$JAIL_DIR" "$(which bash)" --login

