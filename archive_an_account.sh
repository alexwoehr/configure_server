#!/usr/bin/env bash

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


cd /srv

# Create directory containing all info pertaining to this client
# 
# Setup directories
# TODO: expand so it is clearer
mkdir --parents "$ACCOUNT"-account/{varnish,mysql,httpd/sites/"$ACCOUNT",tls/{certs,private},srv/$ACCOUNT/{logs,tmp,htpasswds,notes,ftp,archives}}

# Copy main directory over (apache's documents)
cp -rf $ACCOUNT $ACCOUNT-account/srv

# Copy apache configuration over
# NOTE: current assumption is it lacks extra dir in httpd/sites
eval "cp /etc/httpd/sites/*$ACCOUNT* $ACCOUNT-account/httpd/sites/$ACCOUNT"

# Copy SSL certs, csr's, and keys
eval "cp /etc/pki/tls/certs/*$ACCOUNT* $ACCOUNT-account/tls/certs/"
eval "cp /etc/pki/tls/private/*$ACCOUNT* $ACCOUNT-account/tls/private/"

# TODO: dump mysql tables, copy over varnish configuration
#### Dump and save mysql tables
# Use chroot if available
#### if [[ -e /chroot/mysql ]]; then
####   pushd /chroot/mysql
#### else
####   pushd /
#### fi
#### chroot . mysqldump -u root -p --skip-lock-tables smf > ~-/$ACCOUNT-account/mysql/smf.sql

# Copy varnish configuration over
# Use chroot if available
if [[ -e /chroot/varnish ]]; then
  pushd /chroot/varnish
else
  pushd /
fi

cp -r etc/varnish/$ACCOUNT ~-/$ACCOUNT-account/varnish/

popd

# Compress and encrypt the directory
tar cf "$ACCOUNT"-account{.tar,}
xz "$ACCOUNT"-account.tar
cat "$ACCOUNT"-account.tar.xz | gpg --symmetric --batch --passphrase="$ENCRYPTION_KEY" > "$ACCOUNT"-account.tar.xz.gpg

# TODO: Clean up extra files we generated
# 
#rm -rf "$ACCOUNT"-account{.tar{.xz,},/}

pushd /chroot/mysql/root
unxz 3foldx.sql.gpg.xz
gpg --decrypt --batch --passphrase="$ENCRYPTION_KEY" 3foldx.sql.gpg
popd

echo "Account tarball generated. Saved to $ACCOUNT-account.tar.xz.gpg"

# Standard directories in an account tarball
# mkdir --parents "$ACCOUNT"-account/{httpd/sites/"$ACCOUNT",tls/{certs,private},srv/$ACCOUNT/{logs,tmp,www.$ACCOUNT.com,testing.$ACCOUNT.com,htpasswds,notes,ftp,archives}}

