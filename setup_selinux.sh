
source ui.inc

#######################################
#
#
ui_section "Install Dependencies"

item="basic packages"
task="Installing $item"
ui_start_task "$task"
  yum --assumeyes install screen lftp lsof atop tcpdump pv wget atop git \
  | ui_escape_output yum
ui_end_task "$task"

item="SELinux packages"
task="Installing $item"
ui_start_task "$task"
  yum --assumeyes install checkpolicy libsel* sel* {libselinux{,-utils},libsetools,selinux-policy-{minimum,mls,targeted},policycoreutils,binutils,setools{,-console}}{,-devel} \
  | ui_escape_output yum
ui_end_task "$task"

#######################################
#
#
ui_section "Rebuild Kernel"

task="Enforce SELinux in Grub"
ui_start_task "$task"
  for file in /etc/grub.conf /boot/grub/grub.conf /boot/grub/menu.lst; do
    sed --in-place "s/^kernel .boot.vmlinuz-.*/\0 selinux=1 security=selinux enforcing=1/" "$file"
    ui_print_note "Added enforcements in $file"
  done
ui_end_task "$task"

task="Update any packages as necessary"
ui_start_task "$task"
  yum --assumeyes update \
  | ui_escape_output yum
ui_end_task "$task"

task="Build our own, new kernel package..."
ui_start_task "$task"
  ui_note "Step 1: mkinitrd"
  /sbin/new-kernel-pkg --package kernel --mkinitrd --make-default --dracut --depmod --install `uname --kernel-release`
  ui_note "Step 2: rpm post hook"
  /sbin/new-kernel-pkg --package kernel --rpmposttrans 3.10.48-55.140.amzn1.x86_64
ui_end_task "$task"

task="Rebuild SELinux policy"
ui_start_task "$task"
  semodule --noreload --build
ui_end_task "$task"

#######################################
#
#
ui_section "Prepare for Reboot"

task="Relabel root filesystem at next reboot..."
ui_start_task "$task"
  touch /.autorelabel
ui_end_task "$task"

ui_print_note "Friend, it's time to reboot!"
