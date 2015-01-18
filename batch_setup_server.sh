#!/usr/bin/env bash

# INITIALIZATION
#
# Load libraries -- this is all we need
source ./ui.inc
source ./functions.inc

# Procure commandline arguments

if [[ -z $1 ]]; then

  cat <<END

Invocation error: no host specified.

Usage: $0 <host> <root password on server>

Example: ssh-add ec2.pem && $0 ec2-user@MyAmazonHost SuperSecretRootPassword

Error Message: Please specify a host to setup.

END

  echo -e "Aborting...\n"
  exit 99
fi

HOST="$1"

if [[ -z $2 ]]; then
  echo "No root password found."
  echo "Aborting..."
  exit 99
fi

ROOT_PASSWORD="$2"

# We have to go superuser because sudo -s doesn't work with a tty.
SSH_CMD="ssh $HOST su root"

#######################################
# Update and restart
ui_section "Installing updates since initial server image"

source <(
  ui_prompt_macro "Install updates since $HOST was imaged? [y/N]" proceed n
)

if [[ $proceed == "y" ]]; then

  ui_start_task "Updating $HOST"

  $SSH_CMD <<-END_CMDS | ui_escape_output "yum update"
	$ROOT_PASSWORD
	yum --assumeyes install git
	yum --assumeyes update
	END_CMDS

  ui_print_note "Done. Please restart from AWS console."

  ui_end_task "Updating $HOST"

else

  ui_print_note "OK, no action taken"

fi

#######################################
# Download our setup scripts
ui_section "Install setup scripts"

source <(
  ui_prompt_macro "Install suite of setup scripts? [y/N]" proceed n
)

if [[ $proceed == "y" ]]; then

  ui_start_task "Install Setup Scripts"

  $SSH_CMD <<-END_CMDS | ui_escape_output "git clone"
	$ROOT_PASSWORD
	git clone https://github.com/alexwoehr/configure_server
	cd configure_server
	./install.sh
	END_CMDS

  ui_end_task "Install Setup Scripts"

else

  ui_print_note "OK. Nothing else to do."
  ui_print_note "Exiting..."
  exit 0

fi

#######################################
# Create setup script and compile SELinux
ui_section "Recompile kernel with SELinux"

source <(
  ui_prompt_macro "Should we setup selinux? [y/N]" install_selinux n
)

if [[ $install_selinux == "y" ]]; then

  ui_start_task "Setup SELinux"

  $SSH_CMD <<-END_CMDS | ui_escape_output "setup_selinux"
	$ROOT_PASSWORD
	cd /var/lib/setup_script
	yes \
	  | ./setup_selinux.sh
	END_CMDS

  ui_print_note "Done. Please restart from AWS console."

  ui_end_task "Setup SELinux"

else

  ui_print_note "OK, no action taken"

fi

#######################################
# Partitioning
# currently only works if you also use selinux
if [[ $install_selinux == "y" ]]; then
  ui_section "Partitioning"

  source <(
    ui_prompt_macro "Should we setup default partitioning system? [y/N]" install_partitions n
  )

  if [[ $install_partitions == "y" ]]; then

    ui_start_task "Setup partitions"

    $SSH_CMD <<-END_CMDS | ui_escape_output "setup_partitions"
	$ROOT_PASSWORD
	cd /var/lib/setup_script
	yes \
	  | ./setup_partitions.sh
	END_CMDS

    ui_print_note "Done. You may want to restart from AWS console."

    ui_end_task "Setup partitions"

  fi
else
  ui_print_note "Skipping partitioning because selinux was not enabled."
fi

#######################################
# Hardening
ui_section "NSA hardening"

source <(
  ui_prompt_macro "Run hardening script on the server? [y/N]" proceed n
)

if [[ $proceed == "y" ]]; then

  ui_start_task "Hardening server $HOST"

  $SSH_CMD <<-END_CMDS | ui_escape_output "setup_hardening"
	$ROOT_PASSWORD
	cd /var/lib/setup_script
	yes \
	  | ./setup_hardening.sh
	END_CMDS

  ui_print_note "Done. You may want to restart from AWS console."

  ui_end_task "Hardening server $HOST"

else

  ui_print_note "OK, did not harden server."

fi

#######################################
# Chroots
ui_section "Standard Chroots"

source <(
  ui_prompt_macro "Run chroot scripts on the server? [y/N]" proceed n
)

if [[ $proceed == "y" ]]; then

  ui_start_task "Installing chroots on $HOST"

  # setup loops
  $SSH_CMD <<-END_CMDS | ui_escape_output "prelude"
	$ROOT_PASSWORD
	mkdir --parents /chroot/Loops/
	END_CMDS

  # varnish
  $SSH_CMD <<-END_CMDS | ui_escape_output "install_varnish_chroot"
	$ROOT_PASSWORD
	cd /var/lib/setup_script
	./install_varnish_chroot.sh
	END_CMDS

  # mysql
  $SSH_CMD <<-END_CMDS | ui_escape_output "install_mysql_chroot"
	$ROOT_PASSWORD
	cd /var/lib/setup_script
	./install_mysql_chroot.sh
	END_CMDS

  # apache
  $SSH_CMD <<-END_CMDS | ui_escape_output "install_apache_chroot"
	$ROOT_PASSWORD
	cd /var/lib/setup_script
	./install_apache_chroot.sh
	END_CMDS

  ui_print_note "Done. You may want to restart from AWS console."

  ui_end_task "Installing chroots on $HOST"

else
  ui_print_note "OK, no action taken"
fi

