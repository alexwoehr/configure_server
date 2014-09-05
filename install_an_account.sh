#!/usr/bin/env bash

###########################
#
# Introduction
# 
# This file is used to archive a client account into a compressed, encrypted archive.
# 
# Parameters:
# - $ACCOUNT_PKG: Path to the file that you are unpacking
# - $ENCRYPTION_KEY: key to encrypt / decrypt the archive

###########################
#
# Variables and Global Imports
# 
# Function includes
source ./ui.inc
source ./functions.inc

# Standard setups
source ./setup_vars.sh \
|| (ui_print_note "Cannot find setup_vars.sh. Exiting..." && exit 3)

# Limit Command
# TODO: How to rate limit dynamically based on how intensive a specific process is?
LIMIT_CMD="pv --rate-limit 1M --quiet"

# Facilitate quitting top level script
trap "exit 99" TERM
export TOP_PID=$$

# Utilities
die_hard() {
  kill -s TERM "$TOP_PID"
}

###########################
#
# Global imports
# 
# Function includes


# Main function of script
main() {
  local proceed
  local ACCOUNT_PKG
  local ENCRYPTION_KEY

  ########################
  # Script Parameters: currently ACCOUNT and ENCRYPTION KEY
  source <(
    verify_options_macro "$@"
  )

  # Get other vars: ACCOUNT, ACCOUNT_DIR
  source <(
    vars_macro "$@"
  )

  ########################
  # Unpack the file
  source <(
    ui_prompt_macro "Unpack the account file? [y/N]" proceed n
  )
  if [[ $proceed != "y" ]]; then
    ui_print_note "OK, skipping..."
  else
    ui_start_task "Unpacking"
    unpack_archive "$ACCOUNT_PKG" "$ENCRYPTION_KEY"
    ui_end_task "Unpacking"
  fi

  ########################
  # Distribute the pieces of the account through the system
  source <(
    ui_prompt_macro "Install unpacked archive? [y/N]" proceed n
  )
  if [[ $proceed != "y" ]]; then
    ui_print_note "OK, skipping..."
  else
    ui_start_task "Installing"
    install_archive "$ACCOUNT_PKG"
    ui_end_task "Installing"
  fi

  ui_print_note "Operation completed."

  ui_print_note "Account $ACCOUNT deployed from tarball."

}

# verify_options_macro: Verify options.
# Exports ACCOUNT and ENCRYPTION_KEY
verify_options_macro() {

  # ACCOUNT_PKG: Which file are we unpacking?
  # required
  if [[ -z $1 ]]; then
    ui_print_note "No file found."
    ui_print_note "Aborting..."

    # Die hard
    die_hard
  fi

  local ACCOUNT_PKG="$1"

  # ENCRYPTION_KEY: for decrypting the archive
  # read if they didn't provide this
  if [[ -z $2 ]]; then
    ui_print_note "No encryption key found."
    ui_print_note "Please enter it now."
    source <(
      ui_read_macro ENCRYPTION_KEY
    )
  else
    ENCRYPTION_KEY="$2"
  fi

  # Pass back variables
  cat <<END_MACRO
    ACCOUNT_PKG="$ACCOUNT"
    ENCRYPTION_KEY="$ENCRYPTION_KEY"
END_MACRO

}

# Instantiate this macro to import general vars into your function
# Currently:
# - ACCOUNT_DIR: directory where account archive is being (has been) assembled
vars_macro() {
  # Get arguments
  local ACCOUNT_PKG="$1"

  # Generate vars
  # Derive account name from path
  # Remove directory
  local ACCOUNT_PKG_FILENAME="${ACCOUNT_PKG##*/}";
  # Remove extensions
  local ACCOUNT="${ACCOUNT_PKG_FILENAME%%.*}";

  # Get source directory
  # Remove the filename (including extensions)
  local SOURCE_DIR="${ACCOUNT_PKG#$ACCOUNT_PKG_FILENAME}"

  # Get unpacked archive directory
  # Remove the filename (including extensions)
  local ACCOUNT_DIR="${SOURCE_DIR}/${ACCOUNT}-account"

  # Pass back new vars
  cat <<END_MACRO
  local ACCOUNT_PKG_FILENAME="$ACCOUNT_PKG_FILENAME"
  local ACCOUNT="$ACCOUNT"
  local SOURCE_DIR="$SOURCE_DIR"
  local ACCOUNT_DIR="$ACCOUNT_DIR"
END_MACRO

}

###########################
#
# Unpack Archive
#
# Unpacks an encrypted, tarred file into a directory. (If it's a delta, unpacks the delta.)
# 
unpack_archive() {
  local ACCOUNT_PKG="$1"
  local ENCRYPTION_KEY="$2"

  source <(
    vars_macro "$ACCOUNT_PKG"
  )

  # Decrypt
  ui_print_note "Decrypting file $ACCOUNT_PKG..."

  # After decryption, loses the .gpg extension
  local decrypted_file="${ACCOUNT_PKG%.gpg}"
  cat "$ACCOUNT_PKG" \
    | gpg --batch --decrypt --passphrase="$ENCRYPTION_KEY" \
    | $LIMIT_CMD \
    > "$decrypted_file"
  
  ui_print_note "OK, decrypted file."
  ui_print_note "Decompressing file $decrypted_file..."

  # After decompression, loses the .xz extension
  local decompressed_file="${decrypted_file%.xz}"
  unxz -c "$decrypted_file" \
    | $LIMIT_CMD \
    > $decompressed_file

  local is_delta
  source <(
    ui_prompt_macro "Is ${decompressed_file##*/} an rdiff delta? [y/N]" is_delta n
  )

  if [[ "y" != $is_delta ]]; then
    ui_print_note "OK, skipping delta generation."
  else
    ui_print_note "Generating new archive from deltas..."
    local OLD_ARCHIVE
    source <(
      ui_prompt_macro "Please enter the path of the old archive." OLD_ARCHIVE n
    )

    # TODO: handle dependencies a LOT more gracefully
    ui_print_note "Installing dependencies as necessary..."
    yum --assumeyes --enablerepo=epel install rdiff-backup

    ui_print_note "Patching based on deltas..."

    rdiff patch \
      "$OLD_ARCHIVE" \
      "$OLD_ARCHIVE_SIGS" \
      "$ACCOUNT_DIR.tar"

  fi

  # Either way, previous branch must end with a $ACCOUNT_DIR.tar file.

  # Expand tar archive into directory
  ui_print_note "Expanding into the account directory..."
  tar xf "$ACCOUNT_DIR.tar"

  ui_print_note "Done unpacking archive"

}

###########################
#
# Install each set of files
#
# Distribute pieces around the system, where they need to go.
# 
install_archive() {
  local ACCOUNT_PKG="$1"
  local proceed

  source <(
    vars_macro "$ACCOUNT_PKG"
  )

  ################
  # Apache
  #
  source <(
    ui_prompt_macro "Install resources for apache server daemon (conf, docroot, tls)? [Y/n]" proceed y
  )
  if [[ $proceed == "y" ]]; then
    ui_start_task "Installing resources for apache"
    install_archive_apache "$ACCOUNT_PKG"
    ui_end_task "Installing resources for apache"
  fi

  ################
  # Varnish
  #
  source <(
    ui_prompt_macro "Install resources for varnish daemon (conf)? [Y/n]" proceed y
  )
  if [[ $proceed == "y" ]]; then
    ui_start_task "Installing resources for varnish"
    install_archive_varnish "$ACCOUNT_PKG"
    ui_end_task "Installing resources for varnish"
  fi

  ################
  # MySQL
  #
  source <(
    ui_prompt_macro "Install resources for mysql daemon (databases)? [Y/n]" proceed y
  )
  if [[ $proceed == "y" ]]; then
    ui_start_task "Installing resources for mysql"
    install_archive_mysql "$ACCOUNT_PKG"
    ui_end_task "Installing resources for mysql"
  fi

}

###########################
#
# Install apache resources for this account
#
install_archive_apache() {
  local ACCOUNT_PKG="$1"

  source <(
    vars_macro "$ACCOUNT_PKG"
  )

  # Decrypt
  ui_print_note "Decrypting file $ACCOUNT_PKG..."

  # TODO: check if there's an existing account before clobbering

  local proceed
  local APACHE_ROOT

  ###########################
  #
  # Find root for apache
  # 

  # Check for existence of standard chroot
  if [[ -e "/chroot/apache" ]]; then
    source <(
      ui_prompt_macro "Found apache chroot. Use it to gather apache resources? [Y/n]" proceed y
    )

    if [[ $proceed == "y" ]]; then
      ui_print_note "OK, using /chroot/apache"
      APACHE_ROOT="/chroot/apache"
    fi
  fi

  # If no apache root yet, default to system root
  if [[ -z $APACHE_ROOT ]]; then
    source <(
      ui_prompt_macro "Enter root of apache system? (system root is default) [/]" APACHE_ROOT "/"
    )
  fi

  ###########################
  #
  # Distribute pieces
  # 

  # Use root we decided on
  pushd "$APACHE_ROOT"

  # Merge into apache's docroot
  cp -rf "$ACCOUNT_DIR"/srv/* srv/.

  # Merge configuration
  cp -vrf "$ACCOUNT_DIR"/httpd/* etc/httpd/.
  cp -vrf "$ACCOUNT_DIR"/tls/* etc/pki/tls/.
  cp -vrf "$ACCOUNT_DIR"/varnish/* etc/varnish/.

  # Leave apache chroot, if applicable
  popd

}

###########################
#
# Install varnish resources for this account
#
install_archive_varnish() {
  local ACCOUNT_PKG="$1"

  source <(
    vars_macro "$ACCOUNT_PKG"
  )

  # TODO: check if there's an existing account before clobbering

  local proceed
  local VARNISH_ROOT

  ###########################
  #
  # Find root for varnish
  # 

  # Check for existence of standard chroot
  if [[ -e "/chroot/varnish" ]]; then
    source <(
      ui_prompt_macro "Found varnish chroot. Use it to gather varnish resources? [Y/n]" proceed y
    )

    if [[ $proceed == "y" ]]; then
      ui_print_note "OK, using /chroot/varnish"
      VARNISH_ROOT="/chroot/varnish"
    fi
  fi

  # If no varnish root yet, default to system root
  if [[ -z $VARNISH_ROOT ]]; then
    source <(
      ui_prompt_macro "Please type the root of varnish system? (system root is default) [/]" VARNISH_ROOT "/"
    )
  fi

  cp -vrf $ACCOUNT_DIR/varnish/* etc/varnish/.

}

###########################
#
# Install mysql resources for this account
#
install_archive_mysql() {
  local ACCOUNT_PKG="$1"

  source <(
    vars_macro "$ACCOUNT_PKG"
  )

  # TODO: check if there's an existing account before clobbering

  local proceed
  local MYSQL_ROOT

  ###########################
  #
  # Find root for mysql
  # 

  # Check for existence of standard chroot
  if [[ -e "/chroot/mysql" ]]; then
    source <(
      ui_prompt_macro "Found mysql chroot. Use it to gather mysql resources? [Y/n]" proceed y
    )

    if [[ $proceed == "y" ]]; then
      ui_print_note "OK, using /chroot/mysql"
      MYSQL_ROOT="/chroot/mysql"
    fi
  fi

  # If no mysql root yet, default to system root
  if [[ -z $MYSQL_ROOT ]]; then
    source <(
      ui_prompt_macro "Please type the root of mysql system? (system root is default) [/]" MYSQL_ROOT "/"
    )
  fi

  pushd "$MYSQL_ROOT"

  local CHROOT_CMD="chroot ."

  # TODO: use different users other than mysql root
  ui_press_any_key

  local db_filepath
  for db_filepath in $ACCOUNT_DIR/mysql/*.sql; do

    # Get db name
    local db_filename="${db_filepath##*/}"
    local db="${db_filename%.*}"

    # Create the database
    source <(
      ui_prompt_macro "Okay to create mysql database $db from file $db_filename?" proceed n
    )

    if [[ "y" != $proceed ]]; then
      ui_print_note "OK, skipping file $db_filename..."
    else
      ui_print_note "Creating database $db from $db_filename..."

      ui_print_note "Enter your mysql root password:"

      # Ensure the database is there
      echo "CREATE DATABASE `$db`;" | $CHROOT_CMD mysql -B -u root -p  2>&1

      # Populate the database
      $CHROOT_CMD mysql -B -u root -p "$db" < "$db_path"

      ui_print_note "Finished with database $db."
    fi

  done

  # Leave mysql chroot
  popd

}

###########################
#
# Body
#
# Execute main function
main "$@"

