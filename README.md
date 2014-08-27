
Functions

* Setup SELinux on amazon linuxc
* Format system according to a secure partitioning scheme. Limit log partition so it does not take down the rest of your system. Limit actions on mount points as much as possible.
* Examines the system for over 40 points from the NSA guidelines for securing RHEL
* Install varnish, mysql, and apache in chroot jails.

Steps to Demonstrate Entire Process

* Create new amazon linux server, M3.large
* Setup three drives, xvda with 24 GB, xvdb with 24 GB, and xvde with 960 GB
* Start server and log in
* update server and restart (you need the updated kernel)
* Install git
* Clone this repository
* Execute: install.sh
* Execute: cd /var/lib/setup_script
* Execute: yes | ./setup_selinux.sh
* Execute: shutdown -r now
* Log in again
* Execute: yes | ./setup_partitions.sh
* Execute: shutdown -r now
* Log in again
* Execute: yes | ./setup_hardening.sh
* Execute: ./install_varnish_chroot.sh
* Execute: ./install_mysql_chroot.sh
* Execute: ./install_apache_chroot.sh
* You are all setup!

Greetings. Welcome to Setup Script.

DO THIS FIRST
After unzipping the archive, run "./install.sh" to setup and configure these scripts.

This directory is useful for setting up a new server with basic scripts for installing, configuring firewalls, and hardening a server.

After setting up on the server, this directory may be deleted if you choose.

DIRECTORY CONTENTS
Initial, setup scripts are directly in the directory.

Subdirectories:
  - scripts: add_ftp.sh -- this adds an ftp user, based on our configuration
  - samples: sample configuration, meant as starters for various services
  - data: data used by different sections of the script

SYSTEM EFFECTS

install.sh:
  - Creates and copies files from setup directory to /var/lib/setup_script
  - Creates /var/run/setup_script to store temporary files for our scripts
setup_all.sh:
  - TODO
  - Execute all setup scripts in the right order
setup_selinux.sh:
  - Modifies grub.conf and SELinux configuration
  - Enables SELinux
  - You should reboot after running this file, as other scripts assume SELinux
setup_partitions.sh:
  - Optional
  - You should run this immediately after running setup, if you're going to run it at all
  - Sets up partitions according to SETUP_DIR/data/partition_cmds.txt
  - Generates filesystems in the new partitions according to SETUP_DIR/data/filesystem_generations_cmds.txt
  - Adds new partitions to fstab based on fstab_template.txt
setup_hardening.sh:
  - TODO: FINISH
  - May be run on a server in operation to harden security settings
  - Currently tested for RHEL and Amazon Linux
  - Completes most checkpoints of NSA hardening guide for RHEL
  - Creates an undo script in its TMP_DIR that can undo most changes.
install_all_scripts.sh:
  - Install links for all scripts in LIB_DIR/scripts
  - These are scripts you may want to run to manage the server during normal operation.

System Assumptions

