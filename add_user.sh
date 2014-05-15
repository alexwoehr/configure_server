#!/bin/sh

echo "Not Tested."
exit 255

# Adding a user
echo "1. Create user itself, adding to humans and wheel groups"
echo "2. Add user's ssh key"
echo "3. Create mysql user for this one"

# Check whether this user exists yet

home_dir=/home/$user
useradd --home-dir $home_dir -m --user-group --groups humans,wheel --shell /bin/bash $user \
|| (echo "ERROR: useradd failed with error #$? so exiting..." && exit 1) || exit 1

# Add their ssh key
echo "Please paste their ssh public key in 'ssh-rsa' format:"
read pubkey

l=mkdir $l --parents         $home_dir/.ssh \
&& l=echo  $l                >  $home_dir/.ssh/authorized_keys \
&& l=echo  $l $pubkey        >> $home_dir/.ssh/authorized_keys \
&& l=chown $l -R $user:$user $home_dir/.ssh \
&& l=chmod $l -R u+rw        $home_dir/.ssh \
&& l=chmod $l -R go-rwx      $home_dir/.ssh \
|| (echo "ERROR: Could not save public key. $l failed with error #$?." && exit 1) || exit 1


