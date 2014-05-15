
exit 255 # not implemented yet

# change user's name
usermod -l $new_name $old_name
# change user's home directory
mv /home/$old_name /home/$new_name && usermod -d /home/$new_name $new_name
# change user's gid
groupmod -n $new_name $old_name

