#!/usr/bin/env bash

# TODO:
# * Add --remove option. It's complicated to remove a chroot, unfortunately.
# * Compare against script at http://www.linuxfocus.org/common/src/article225/Config_Chroot.pl.txt (see http://www.linuxfocus.org/English/January2002/article225.shtml)
# * Research SELinux and chroot, SELinux and loop

# TODO: Setup section.
####    # Use DD and PV so you can keep tabs on progress
####    mount -o loop,"$OTHER_OPTIONS" /chroot/Loops/"$CHROOT_NAME".loop "$JAIL_DIR"
####    # Verify that it worked
####    mount | grep "$JAIL_DIR"

# Load libraries
source ./ui.inc
source ./functions.inc

# Setup variables
source ./setup_vars.sh \
  || (echo "Cannot find setup_vars.sh. Exiting..." && exit 3)


readonly pkg_base_download="http://mirror.centos.org/centos/6/os/x86_64/Packages/centos-release-6-5.el6.centos.11.1.x86_64.rpm"

if [[ -z $1 ]]; then
  ui_print_note "You must supply the name of the new chroot to create."
  ui_print_note "Exiting.."
  exit 2
fi

readonly CHROOT_NAME="$1"
readonly JAIL_DIR=/chroot/"$CHROOT_NAME"
readonly CHROOT_LOOP_FILE=/chroot/Loops/"$CHROOT_NAME".loop

ui_start_task "Create chroot loop partition"

if [[ -e "$CHROOT_LOOP_FILE" ]]; then
  ui_print_note "Partition was detected. Nothing to do."
else

  ui_print_note "Partition not detected yet."
  ui_print_note "Building the partition..."

  # Use DD and PV so you can keep tabs on progress
  if [[ -z $CHROOT_SIZE_MEGABYTES ]]; then
    source <(
      ui_prompt_macro "How many MB should the new chroot be? [8000]" CHROOT_SIZE_MEGABYTES 8000
    )

    # Ensure that "yes | $0" idiom works: y is always a normal answer.
    if [[ $CHROOT_SIZE_MEGABYTES == "y" ]]; then
      CHROOT_SIZE_MEGABYTES="8000"
    fi
  fi

  # TODO: Could determine ideal BS size using tool
  dd bs=1M count="$CHROOT_SIZE_MEGABYTES" if=/dev/zero | pv -s "$CHROOT_SIZE_MEGABYTES"M > "$CHROOT_LOOP_FILE"

  # Create filesystem in the loop file
  mkfs.ext4 -F "$CHROOT_LOOP_FILE"
fi

ui_end_task "Create chroot loop partition"

ui_start_task "Mount chroot"

# Mount the loop file
if [[ $(mount | grep --fixed-strings "$JAIL_DIR" | wc -l) == 0 ]]; then
  ui_print_note "Mount point was detected. Not safe to mess with existing sytem."
else
 
  # It's not mounted yet.
  # Need to mount it.
  source <(
    ui_prompt_macro "What mount options to use? [defaults,nodev,nosuid]" CHROOT_MOUNT_OPTIONS "defaults,nodev,nosuid"
  )

  # Ensure that "yes | $0" idiom works: y is always a normal answer.
  if [[ $proceed == "y" ]]; then
    CHROOT_MOUNT_OPTIONS="defaults,nodev,nosuid"
  fi

  mount -o "loop,$CHROOT_MOUNT_OPTIONS" /chroot/Loops/"$CHROOT_NAME".loop "$JAIL_DIR"

  # TODO: Test here whether it's already in fstab. (Previous unclean removal of the chroot jail.)
  source <(
    ui_prompt_macro "Should we add to fstab? [y/N]" proceed n
  )

  if [[ $proceed != "y" ]]; then
    ui_print_note "OK, did not add loop device to fstab"
  else

    # Add to fstab entry
    >> /etc/fstab cat <<END_FSTAB_ENTRY
/chroot/Loops/"$CHROOT_NAME".loop       "$JAIL_DIR"           ext4            "loop,$OTHER_OPTIONS"   1 2
END_FSTAB_ENTRY

    ui_print_note "Added entry to fstab."
    cat /etc/fstab | ui_escape_output "fstab"
    ui_press_any_key
  fi
fi


ui_end_task "Create chroot file system"

ui_start_task "Create chroot jail directory"

mkdir --parents "$JAIL_DIR"
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

# Copy over the repos
source <(
  ui_prompt_macro "Copy your current repos into the chroot?" proceed n
)
if [[ $proceed != "y" ]]; then
  ui_print_note "OK, no action taken."
else
  cp -rf /etc/yum.repos.d/ "$JAIL_DIR"/etc
  ui_print_note "Copied repos."
fi

ui_end_task "Install all core packages"

ui_start_task "Setup remaining inner directories"

cp "$JAIL_DIR"{/etc/skel/.??*,/root

# Special directories
mount --bind /proc "$JAIL_DIR"/proc
mount --bind /dev "$JAIL_DIR"/dev

# Network DNS resolution
cp {,"$JAIL_DIR"}/etc/resolv.conf

mkdir  --parents    "$JAIL_DIR"/var/run
mkdir  --parents    "$JAIL_DIR"/home/httpd
mkdir  --parents    "$JAIL_DIR"/var/www/html
mkdir  --parents    "$JAIL_DIR"/tmp
chmod  1777         "$JAIL_DIR"/tmp
mkdir  --parents    "$JAIL_DIR"/var/lib/php/session
chown --recursive   root.root "$JAIL_DIR"/var/run
chown root.apache   "$JAIL_DIR"/var/lib/php/session

# Copy important etc configuration
# From link: http://www.cyberciti.biz/faq/howto-run-nginx-in-a-chroot-jail/
# cp -fv /etc/{group,prelink.cache,services,adjtime,shells,gshadow,shadow,hosts.deny,localtime,nsswitch.conf,nscd.conf,prelink.conf,protocols,hosts,passwd,ld.so.cache,ld.so.conf,resolv.conf,host.conf} "$JAIL_DIR"/etc
cp -fv /etc/{prelink.cache,services,adjtime,shells,hosts.deny,localtime,nsswitch.conf,nscd.conf,prelink.conf,protocols,hosts,ld.so.cache,ld.so.conf,resolv.conf,host.conf} "$JAIL_DIR"/etc

# square up CA's in new system
source <(
  ui_prompt_macro "Copy your TLS items including CA authorities into chroot?" proceed n
)
if [[ $proceed != "y" ]]; then
  ui_print_note "OK, no action taken."
else
  mkdir --parents "$JAIL_DIR"/etc/pki/tls/certs
  cp -rfv /etc/pki/tls/certs "$JAIL_DIR"/etc/pki/tls
  ui_print_note "OK, ca authorities have been copied."
fi

# Move list of users over
# passwd is tricky...only copy users that are needed in the chroot
grep -Fe root -e apache -e varnish -e nginx /etc/passwd > "$JAIL_DIR"/etc/passwd

# mysql needs this
if [[ $CHROOT_NAME == "mysql" ]]; then
  cp {,/chroot/mysql}/etc/sysconfig/network
fi

# Setup SELinux permissions
# APACHE only
setsebool httpd_disable_trans 1

ui_end_task "Setup remaining inner directories"


ui_print_note "Setup is finished."
ui_print_note "Now you should be able to chroot into the new system and complete any remaining setup by using the following command:"

cat <<END_COMMAND
  chroot "$JAIL_DIR" "$(which bash)" --login
END_COMMAND

