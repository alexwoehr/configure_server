#!/usr/bin/env bash

# TODO:
# * Add --remove option. It's complicated to remove a chroot, unfortunately.

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

# passwd is tricky...only copy users that are needed in the chroot
grep -Fe apache -e varnish -e nginx /etc/passwd > "$JAIL_DIR"/etc/passwd

# Setup SELinux permissions
# APACHE only
setsebool httpd_disable_trans 1

ui_end_task "Setup remaining inner directories"


ui_print_note "Setup is finished."
ui_print_note "Now you should be able to chroot into the new system and complete any remaining setup by using the following command:"

cat <<END_COMMAND
  chroot "$JAIL_DIR" "$(which bash)" --login
END_COMMAND

