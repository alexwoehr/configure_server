#!/usr/bin/env bash

# Load libraries
source ./ui.inc
source ./functions.inc

# Setup variables
source ./setup_vars.sh \
  || (echo "Cannot find setup_vars.sh. Exiting..." && exit 3)

readonly CHROOT_NAME="apache"
readonly CHROOT_JAIL_DIR=/chroot/"$CHROOT_NAME"
readonly CHROOT_LOOP_FILE=/chroot/Loops/"$CHROOT_NAME".loop

readonly USER="$CHROOT_NAME"
readonly CHROOT_USER=chroot_"$USER"

# Packages required for apache / php
readonly PACKAGE_LIST="httpd httpd-devel php php-devel php-mysql php-pear php-xml php-mysql php-cli php-imap php-gd php-pdo php-mbstring php-common php-ldap"

# Build jail with default parameters
pushd "$LIB_DIR" \
&& yes | ./build_chroot_jail.sh "$CHROOT_NAME"
popd

# install packages
chroot "$CHROOT_JAIL_DIR" bash --login <<END_COMMANDS | ui_escape_output "yum"
  yum --assumeyes install $PACKAGE_LIST
END_COMMANDS

# Copy over sample conf files
if [[ -e "$LIB_DIR"/samples/"$CHROOT_NAME".defaults ]]; then
  cp -v "$LIB_DIR"/samples/"$CHROOT_NAME".defaults "$CHROOT_JAIL_DIR"/etc/sysconfig/"$CHROOT_NAME"
fi

if [[ -e "$LIB_DIR"/samples/"$CHROOT_NAME".cnf ]]; then
  cp -v "$LIB_DIR"/samples/"$CHROOT_NAME".cnf "$CHROOT_JAIL_DIR"/etc/
fi

# Copy over some network stuff
cp /etc/sysconfig/network "$CHROOT_JAIL_DIR"/etc/sysconfig/network
cp /etc/hosts "$CHROOT_JAIL_DIR"/etc/hosts

# Custom 3Fold stuff
# mount xvde5 (srv) within the apache chroot
umount /dev/xvde5 \
&& rm -rf --one-file-system "$CHROOT_JAIL_DIR"/srv/* \
&& mount -o defaults,nodev,nosuid /dev/xvde5 "$CHROOT_JAIL_DIR"/srv

# link some crucial things from the main server into the chroot. (you can jump in but you can't jump out)
rm -rf --one-file-system /srv
ln -s "$CHROOT_JAIL_DIR"/srv /srv # link srv root
rm -rf --one-file-system /etc/httpd
ln -s "$CHROOT_JAIL_DIR"/etc/httpd/ /etc/httpd # link httpd configuration root

# Change srv direcotry we just setup
chroot "$CHROOT_JAIL_DIR" chown -R apache:apache /srv

# Create contained data files (in httpd owned directories) and update my.cnf to use them
chroot . bash --login <<END_CMDS
  for dir in log run; do
    mkdir --parents /var/\$dir/_apache-container
    mv /var/\$dir/{apache*,httpd*,_apache-container/}
    mv /var/\$dir/{_,}apache-container
    chown -R apache:apache /var/\$dir/apache-container
  done

  # Lock file
  mkdir --parents /var/lock/subsys/apache-container
  touch /var/lock/subsys/apache-container/httpd
  chown -R apache:apache /var/lock/subsys/apache-container
END_CMDS

# Fix broken links now
rm /etc/httpd/run
ln -s /var/run/apache-container/httpd /etc/httpd/run
rm /etc/httpd/logs
ln -s /var/log/apache-container/httpd /etc/httpd/logs

cd "$CHROOT_JAIL_DIR"

# sed scripts to fix a few things in configuration

# Change pid and lock file in init script to use different file
#
cat >> etc/sysconfig/httpd <<END
  PIDFILE=/var/run/httpd-container/httpd.pid # line added by install_apache_chroot.sh
  LOCKFILE=/var/lock/subsys/httpd-container/httpd # line added by install_apache_chroot.sh
END

# Fix configuration: listen on 8000 instead of 80
#
search_value='Listen 80'
new_value='Listen 8080'
change_line=$(grep --line-number --fixed-strings --line-regexp -e "$search_value" etc/httpd/conf/httpd.conf | cut -d: -f1 | head -1 )
sed --in-place "${change_line}c\\\n$new_value" /etc/httpd/conf/httpd.conf

# Fix configuration: Document Root to /srv
#
search_value='DocumentRoot "/var/www/html"'
new_value='DocumentRoot "/srv"'
change_line=$(grep --line-number --fixed-strings --line-regexp -e "$search_value" etc/httpd/conf/httpd.conf | cut -d: -f1 | head -1 )
sed --in-place "${change_line}c\\\n$new_value" /etc/httpd/conf/httpd.conf

search_value='<Directory "/var/www/html">'
new_value='<Directory "/srv">'
change_line=$(grep --line-number --fixed-strings --line-regexp -e "$search_value" etc/httpd/conf/httpd.conf | cut -d: -f1 | head -1 )
sed --in-place "${change_line}c\\\n$new_value" /etc/httpd/conf/httpd.conf

# Set hostname; bit of a dirty trick
hostname="$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 | sed 's/$/.xip.io/')"
chroot "$CHROOT_JAIL_DIR" hostname -F "$hostname"
# Make sure it resolves even if xip.io goes down
echo "127.0.0.1\t$hostname" > "$CHROOT_JAIL_DIR"/etc/hosts

# Step down privileges and initiate daemon
cd "$CHROOT_JAIL_DIR" \
&& chroot --userspec="$USER" "$CHROOT_JAIL_DIR" service httpd start

# TODO: Create options for--
# - do not create dev (? does apache need dev and proc?)
# - do not copy executables
# - setup daemon things automatically
