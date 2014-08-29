#!/usr/bin/env bash

# TODO: Put all long-running commands on a progress bar, and add lots of info so the user knows how long it's going to take.

if [[ -z $1 ]]; then
  echo "No account found."
  echo "Aborting..."
  exit 99
fi

ACCOUNT="$1"

if [[ -z $2 ]]; then
  echo "No encryption key found."
  echo "Please enter it now."
  read ENCRYPTION_KEY
else
  ENCRYPTION_KEY="$2"
fi

pushd /srv

# First, Untar the main folder, that contains all the data
< "$ACCOUNT"-account.tar.xz.gpg \
  gpg --decrypt --batch --passphrase="$ENCRYPTION_KEY" \
> "$ACCOUNT"-account.tar.xz

unxz "$ACCOUNT"-account.tar.xz
tar xf "$ACCOUNT"-account.tar

# Setup directories
# mkdir --parents "$ACCOUNT"-account/{varnish,mysql,httpd/sites/"$ACCOUNT",tls/{certs,private},srv/$ACCOUNT/{logs,tmp,www.$ACCOUNT.com,testing.$ACCOUNT.com,htpasswds,notes,ftp,archives}}

# TODO: some kind of backups, plus protecting from hurting other accounts
# TODO: check if there's an existing account before clobbering

# Use the right directory if there's an apache chroot
if [[ -e /chroot/apache ]]; then
  pushd /chroot/apache
else
  pushd /
fi

# Copy main directory over (apache's documents)
cp -rf ~-/$ACCOUNT-account/srv/* srv/

# Merge everything into the system
cp -rf ~-/$ACCOUNT-account/httpd/* etc/httpd/
cp -rf ~-/$ACCOUNT-account/tls/* etc/pki/tls/
cp -rf ~-/$ACCOUNT-account/varnish/* etc/varnish/

# Leave apache chroot, if applicable
popd


# use chroot if possible
if [[ -e /chroot/varnish ]]; then
  new_dir=/chroot/varnish
else
  new_dir=/
fi

pushd $new_dir
cp -rf ~-/$ACCOUNT-account/varnish/* etc/varnish/
popd

# TODO: Clean up extra files we generated
# 

popd

#### MYSQL ARCHIVE
#### pushd /chroot/mysql/root
#### mysqldump -u root -p --skip-lock-tables 3foldx | gpg --symmetric --batch --passphrase="$ENCRYPTION_KEY" > 3foldx.sql.gpg

echo "Account deployed from tarball."

# Standard directories in an account tarball
# mkdir --parents "$ACCOUNT"-account/{httpd/sites/"$ACCOUNT",tls/{certs,private},srv/$ACCOUNT/{logs,tmp,www.$ACCOUNT.com,testing.$ACCOUNT.com,htpasswds,notes,ftp,archives}}

