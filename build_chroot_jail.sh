#!/usr/bin/env bash

# TODO:
# * Add --remove option. It's complicated to remove a chroot, unfortunately.
# * Compare against script at http://www.linuxfocus.org/common/src/article225/Config_Chroot.pl.txt (see http://www.linuxfocus.org/English/January2002/article225.shtml)
# * Research SELinux and chroot, SELinux and loop
# * Ensure no chroot jail

# Load libraries
source ./ui.inc
source ./functions.inc

# Setup variables
source ./setup_vars.sh \
  || (echo "Cannot find setup_vars.sh. Exiting..." && exit 3)


##
## FUNCTIONS
##

# Function to run rpm locally
rpm_local() {
  rpm --root="$CHROOT_JAIL_DIR" "$@"
}

# Function to run yum locally
yum_localized() {
  yum --installroot="$CHROOT_JAIL_DIR" "$@"
}

# Function to run yum chrooted
yum_chrooted() {
  chroot "$CHROOT_JAIL_DIR" yum "$@"
}

# Extracts centos release from repository html (*winces*)
# and returns in stdout
stream_extract_centos_release_name() {
  tr '"' "\n" \
  | tr --delete --complement $'\n0-9A-Za-z._-' \
  | grep "^$CENTOS_RELEASE_PATTERN$"
}

##
## VARIABLES
##

readonly CENTOS_RELEASE_DIR='http://mirror.centos.org/centos/6.6/os/x86_64/Packages'
readonly CENTOS_RELEASE_KEY='http://mirror.centos.org/centos/6.6/os/x86_64/RPM-GPG-KEY-CentOS-6'
readonly CENTOS_RELEASE_PATTERN='centos-release-6-6.el6.centos.*.x86_64.rpm'

readonly DEFAULT_CHROOT_SIZE_MEGABYTES=8000
declare -i DEFAULT_CHROOT_SIZE_MEGABYTES

if [[ -z $1 ]]; then
  ui_print_note "You must supply the name of the new chroot to create."
  ui_print_note "Exiting.."
  exit 2
fi

# Name of the chroot itself. This will determine many other settings.
readonly CHROOT_NAME="$1"

# Location of the jail
readonly CHROOT_JAIL_DIR=/chroot/"$CHROOT_NAME"

# Loop file that contains the chroot filesystem
readonly CHROOT_LOOP_FILE=/chroot/Loops/"$CHROOT_NAME".loop

# User that owns the chroot
readonly CHROOT_USER=chroot_"$CHROOT_NAME"

# Group that owns the chroot
readonly CHROOT_GROUP=chroot_group

# Packages to install
readonly PACKAGES="yum rpm rpm-build initscripts"

##
## OPERATION
##

ui_start_task "Dependencies"

yum --assumeyes install e2fsprogs curl wget pv

ui_end_task "Dependencies"

ui_start_task "Create chroot loop partition"

ui_print_note "Creating Loop filesystem..."

mkdir --parents/chroot/Loops

if [[ -e "$CHROOT_LOOP_FILE" ]]; then
  ui_print_note "Partition was detected. Nothing to do."
else

  ui_print_note "Partition not detected yet."
  ui_print_note "Building the partition..."

  # Use DD and PV so you can keep tabs on progress
  if [[ -z $CHROOT_SIZE_MEGABYTES ]]; then
    source <(
      ui_prompt_macro "How many MB should the new chroot be? [$DEFAULT_CHROOT_SIZE_MEGABYTES]" CHROOT_SIZE_MEGABYTES "$DEFAULT_CHROOT_SIZE_MEGABYTES"
    )

    # Ensure that "yes | $0" idiom works: y is always a normal answer.
    if [[ $CHROOT_SIZE_MEGABYTES == "y" ]]; then
      CHROOT_SIZE_MEGABYTES="$DEFAULT_CHROOT_SIZE_MEGABYTES"
    fi
  fi

  dd bs=1M count="$CHROOT_SIZE_MEGABYTES" if=/dev/zero | pv -s "$CHROOT_SIZE_MEGABYTES"M > "$CHROOT_LOOP_FILE"
fi

ui_end_task "Create chroot loop partition"

ui_start_task "Create chroot jail directory"

mkdir --parents "$CHROOT_JAIL_DIR"

ui_end_task "Create chroot jail directory"

ui_start_task "Create chroot file system"

# Mount the loop file
if [[ $(mount | grep --fixed-strings "$CHROOT_JAIL_DIR on " | wc -l) != 0 ]]; then
  ui_print_note "Mount point was detected. Not safe to mess with existing sytem."
else

  # Create filesystem in the loop file
  mkfs.ext4 -F "$CHROOT_LOOP_FILE"
 
  # It's not mounted yet.
  # Need to mount it.
  source <(
    ui_prompt_macro "What mount options to use? [defaults,nodev,nosuid]" CHROOT_MOUNT_OPTIONS "defaults,nodev,nosuid"
  )

  # Ensure that "yes | $0" idiom works: y is always a normal answer.
  if [[ $CHROOT_MOUNT_OPTIONS == "y" ]]; then
    CHROOT_MOUNT_OPTIONS="defaults,nodev,nosuid"
  fi

  mount -o "loop,$CHROOT_MOUNT_OPTIONS" /chroot/Loops/"$CHROOT_NAME".loop "$CHROOT_JAIL_DIR"

  # TODO: Test here whether it's already in fstab. (Previous unclean removal of the chroot jail.)
  source <(
    ui_prompt_macro "Should we add to fstab? [y/N]" proceed n
  )

  if [[ $proceed != "y" ]]; then
    ui_print_note "OK, did not add loop device to fstab"
  else

    # Add to fstab entry
    >> /etc/fstab cat <<END_FSTAB_ENTRY
/chroot/Loops/$CHROOT_NAME.loop       $CHROOT_JAIL_DIR           ext4            loop,$CHROOT_MOUNT_OPTIONS   1 2
END_FSTAB_ENTRY

    ui_print_note "Added entry to fstab."
    cat /etc/fstab | ui_escape_output "fstab"
    ui_press_any_key
  fi
fi

ui_end_task "Create chroot file system"

ui_start_task "Setup rpm base"

rpm_local --rebuilddb
rpm_local --import "$CENTOS_RELEASE_KEY"


# Setup package database within container

# - Search for needed repolist in the mirror and pull it.
#   This could fail and get dicey. Final slash is important, too.
curl --silent "$CENTOS_RELEASE_DIR"/ \
| stream_extract_centos_release_name \
| xargs -I% wget --quiet "$CENTOS_RELEASE_DIR"/%

# - Install repolist
#   NOTE: pattern intentionally left unquoted
rpm_local --install --nodeps ./$CENTOS_RELEASE_PATTERN
rm ./$CENTOS_RELEASE_PATTERN

ui_end_task "Setup rpm base"

ui_start_task "Install all core packages"

# unquoted variable expands to multiple words
yum_localized --config=<( echo "[main]" ) --assumeyes install $PACKAGES \
| ui_escape_output "yum"

# Copy over the repos
source <(
  ui_prompt_macro "Copy your additional repos into the chroot? [y/N]" proceed n
)
if [[ $proceed != "y" ]]; then
  ui_print_note "OK, no action taken."
else
  # Omit amazon repos, since this is a CentOS build script!
  ls -d /etc/yum.repos.d/*.repo \
  | grep -v /amzn- \
  | xargs -I% cp % "$CHROOT_JAIL_DIR"/etc/yum.repos.d

  ui_start_task "Updating yum..."

  yum_chrooted --assumeyes clean all \
  && yum_chrooted --assumeyes update \
     | ui_escape_output "yum"

  ui_end_task "Updating yum..."

  ui_print_note "Copied extra repos."
fi

ui_end_task "Install all core packages"

ui_start_task "Setup root skeleton"

cp -v "$CHROOT_JAIL_DIR"{/etc/skel/.??*,/root}

ui_end_task "Setup root skeleton"

ui_start_task "Bind directories"

# Special directories
mount --bind /proc "$CHROOT_JAIL_DIR"/proc
mount --bind /dev "$CHROOT_JAIL_DIR"/dev

ui_end_task "Bind directories"

ui_start_task "Network files and other important directories"

# Network DNS resolution
cp -v {,"$CHROOT_JAIL_DIR"}/etc/resolv.conf

mkdir  --parents    "$CHROOT_JAIL_DIR"/var/run
mkdir  --parents    "$CHROOT_JAIL_DIR"/home/httpd
mkdir  --parents    "$CHROOT_JAIL_DIR"/var/www/html
mkdir  --parents    "$CHROOT_JAIL_DIR"/tmp
chmod  1777         "$CHROOT_JAIL_DIR"/tmp
chown --recursive   root:root "$CHROOT_JAIL_DIR"/var/run
# mkdir  --parents    "$CHROOT_JAIL_DIR"/var/lib/php/session
# chown root:apache   "$CHROOT_JAIL_DIR"/var/lib/php/session

ui_end_task "Network files and other important directories"

ui_start_task "User / group setup"

# Setup user on CHROOT jail
if getent group $CHROOT_GROUP; then
  ui_print_note "Found group $CHROOT_GROUP"
else
  ui_print_note "Creating group $CHROOT_GROUP"
  groupadd "$CHROOT_GROUP"
fi

# -M: means "do not create home directory"
useradd -M --home "$CHROOT_JAIL_DIR" "$CHROOT_USER"
gpasswd --add "$CHROOT_USER" "$CHROOT_GROUP"
chown $CHROOT_USER:$CHROOT_USER "$CHROOT_JAIL_DIR"

# We only give permissions to home and root. In individual chroot scripts, you may want to do more.
for dir in home root; do
  chown -R $CHROOT_USER:$CHROOT_USER "$CHROOT_JAIL_DIR"/$dir
done

ui_start_task "User / group setup"

ui_start_task "Copy important etc configuration"

# From link: http://www.cyberciti.biz/faq/howto-run-nginx-in-a-chroot-jail/
cp -fv /etc/{prelink.cache,services,adjtime,shells,hosts.deny,localtime,nsswitch.conf,nscd.conf,prelink.conf,protocols,hosts,ld.so.cache,ld.so.conf,resolv.conf,host.conf} "$CHROOT_JAIL_DIR"/etc

# square up CA's in new system
source <(
  ui_prompt_macro "Copy your CA authorities into chroot? [y/N]" proceed n
)
if [[ $proceed != "y" ]]; then
  ui_print_note "OK, no action taken."
else
  mkdir --parents "$CHROOT_JAIL_DIR"/etc/pki/tls/certs
  cp -rfv /etc/pki/tls/certs "$CHROOT_JAIL_DIR"/etc/pki/tls
  ui_print_note "OK, ca authorities have been copied."
fi

# Move list of users over
# passwd is tricky...only copy users that are needed in the chroot
for pwdfile in passwd shadow group; do
  grep -Fe root -e "$CHROOT_NAME" -e "$CHROOT_USER" /etc/"$pwdfile" >> "$CHROOT_JAIL_DIR"/etc/"$pwdfile"
done

# Setup SELinux permissions
# APACHE only
ui_print_note "Setting up selinux permissions."
####    apache: # setsebool httpd_disable_trans 1

ui_end_task "Copy important etc configuration"

ui_print_note "Setup is finished."
ui_print_note "Now you should be able to chroot into the new system and complete any remaining setup by using the following command:"

cat <<END_COMMAND
  cd "$CHROOT_JAIL_DIR" && chroot "$CHROOT_JAIL_DIR" su "$CHROOT_USER" -c "$(which bash) --login"
END_COMMAND

