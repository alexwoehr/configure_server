
echo "Installing basic packages..."
yum --assumeyes install screen lftp lsof atop tcpdump pv wget atop \
| sed 's/.*/[yum says] \0/'
echo "Installing selinux packages..."
yum --assumeyes install checkpolicy libsel* sel* {libselinux{,-utils},libsetools,selinux-policy-{minimum,mls,targeted},policycoreutils,binutils,setools{,-console}}{,-devel} \
| sed 's/.*/[yum says] \0/'
echo "Adding SELinux enforcement in grub..."
for file in /etc/grub.conf /boot/grub/grub.conf /boot/grub/menu.lst; do
  sed --in-place "s/^kernel .boot.vmlinuz-.*/\0 selinux=1 security=selinux enforcing=1/" "$file"
done
echo "Now updating all packages..."
yum --assumeyes update
echo "Build our own, new kernel package..."
/sbin/new-kernel-pkg --package kernel --mkinitrd --make-default --dracut --depmod --install `uname -r`

echo 'Rebuilding SELinux policy...'
semodule --noreload --build

echo "Relabel root filesystem at next reboot..."
touch /.autorelabel

echo "Friend, it's time to reboot!"
