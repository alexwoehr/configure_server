
# TODO: Put all long-running commands on a progress bar, and add lots of info so the user knows how long it's going to take.

ACCOUNT=$1
ENCRYPTION_KEY=$2

cd /srv

# First, Untar the main folder, that contains all the data
cat "$ACCOUNT"-account.tar.xz.gpg | gpg --decrypt --batch --passphrase="$ENCRYPTION_KEY" > "$ACCOUNT"-account.tar.xz.gpg
unxz "$ACCOUNT"-account.tar
tar xf "$ACCOUNT"-account.tar "$ACCOUNT"-account

# Setup directories
# mkdir --parents "$ACCOUNT"-account/{varnish,mysql,httpd/sites/"$ACCOUNT",tls/{certs,private},srv/$ACCOUNT/{logs,tmp,www.$ACCOUNT.com,testing.$ACCOUNT.com,htpasswds,notes,ftp,archives}}

# TODO: some kind of backups, plus protecting from hurting other accounts
# TODO: check if there's an existing account before clobbering
# Merge apache documents into the system
cp -rf $ACCOUNT-account/srv/* /srv

# Merge everything into the system
cp -rf $ACCOUNT-account/httpd /etc/
cp -rf $ACCOUNT-account/tls /etc/pki/
cp -rf $ACCOUNT-account/varnish /etc/varnish/

# TODO: dump mysql tables
# TODO: copy over varnish configuration

# Clean up extra files we generated
# 

echo "Account deployed from tarball."

# Standard directories in an account tarball
# mkdir --parents "$ACCOUNT"-account/{httpd/sites/"$ACCOUNT",tls/{certs,private},srv/$ACCOUNT/{logs,tmp,www.$ACCOUNT.com,testing.$ACCOUNT.com,htpasswds,notes,ftp,archives}}

