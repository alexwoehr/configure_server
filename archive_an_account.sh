#!/bin/bash -x

###########################
#
# Introduction
# 
# This file is used to archive a client account into a compressed, encrypted archive.
# 
# Parameters:
# - $ACCOUNT
# - $DESTINATION_DIR: directory that will hold the archive and other files.
# - $ENCRYPTION_KEY: key to encrypt / decrypt the archive

# TODO sectionbelow
# 
# General:
# - [x] move into the /var/lib/setup_script directory and version correctly
# - [ ] cleanup extra files, optionally
# - [ ] better documentation
# - [ ] needs reporting, prompts
# - [ ] all functions should allow rate limiting
# - [ ] handle clobbering
# - [ ] roll patching function into this file
# - [ ] install any packages required by the site
# - [ ] implement subcommand oriented approach, similar to github
# - [ ] add universal long options shared between subcommands
# - [ ] use an xml file to package account data
# - [ ] support nginx configuration
# - [ ] support haproxy configuration
# HTTPD:
# - [ ] handle situation where they haven't updated httpd conf paths properly. Remind them to edit conf fil
# Databases:
# - [ ] support postgres
# - [ ] consider adding "--databases --add-drop-database" to mysqldump, if clobber option is set
# - [ ] when the script tries to grab a database, if there is no database to grab, it will warn the user.
# - [ ] if there is no database that matches the convention, show the user a list of databases, and allow them to select the database to export.
# - [ ] support integrating into my.cnf

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
LIMIT_CMD="pv --limit 4M"

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
  local ACCOUNT
  local DESTINATION_DIR
  local ENCRYPTION_KEY

  ########################
  # Script Parameters: currently ACCOUNT and ENCRYPTION KEY
  source <(
    verify_options_macro "$@"
  )

  ########################
  # Create skeleton for the account
  source <(
    ui_prompt_macro "Create skeleton for the account? [y/N]" proceed n
  )
  if [[ $proceed != "y" ]]; then
    ui_print_note "OK, skipping..."
  else
    ui_start_task "Create Skeleton"
    create_skeleton "$ACCOUNT" "$DESTINATION_DIR"
    ui_end_task "Create Skeleton"
  fi

  ########################
  # Gather the bits and pieces of this account
  source <(
    ui_prompt_macro "Gather resources for this account? [y/N]" proceed n
  )
  if [[ $proceed != "y" ]]; then
    ui_print_note "OK, skipping..."
  else
    ui_start_task "Gather Resources"
    gather "$ACCOUNT" "$DESTINATION_DIR"
    ui_end_task "Gather Resources"
  fi

  ########################
  # Package up the data
  source <(
    ui_prompt_macro "Package the account? [y/N]" proceed n
  )
  if [[ $proceed != "y" ]]; then
    ui_print_note "OK, skipping..."
  else
    ui_start_task "Package Account"
    package "$ACCOUNT" "$DESTINATION_DIR" "$ENCRYPTION_KEY"
    ui_end_task "Package Account"
  fi

}

# verify_options_macro: Verify options.
# Exports ACCOUNT and ENCRYPTION_KEY
verify_options_macro() {

  # ACCOUNT: Which account are we archiving?
  # required
  if [[ -z $1 ]]; then
    ui_print_note "No account found."
    ui_print_note "Aborting..."

    # Die hard
    die_hard
  fi

  ACCOUNT="$1"

  # DESTINATION_DIR: destination for example-account/ directory, example-account.tar.xz.gpg, etc
  # read if they didn't provide this
  if [[ -z $2 ]]; then
    ui_print_note "No destination directory found."
    source <(
      ui_prompt_macro "Please enter directory, or ENTER to default to home? [$(pwd)]" DESTINATION_DIR "$(pwd)"
    )
    ui_print_note "OK, using $DESTINATION_DIR"
  else
    DESTINATION_DIR="$2"
  fi

  # ENCRYPTION_KEY: for encrypting the archive, at the end
  # read if they didn't provide this
  if [[ -z $3 ]]; then
    ui_print_note "No encryption key found."
    ui_print_note "Please enter it now."
    source <(
      ui_read_macro ENCRYPTION_KEY
    )
  else
    ENCRYPTION_KEY="$3"
  fi

  # Pass back variables
  cat <<END_MACRO
    ACCOUNT="$ACCOUNT"
    DESTINATION_DIR="$DESTINATION_DIR"
    ENCRYPTION_KEY="$ENCRYPTION_KEY"
END_MACRO

}

# Instantiate this macro to import general vars into your function
# Currently:
# - ACCOUNT_DIR: directory where account archive is being (has been) assembled
vars_macro() {
  # Get arguments
  local ACCOUNT="$1"
  local DESTINATION_DIR="$2"

  # Generate vars
  local ACCOUNT_DIR="$DESTINATION_DIR/${ACCOUNT}-account"

  # Pass back vars
  cat <<END_MACRO
  local ACCOUNT_DIR="$ACCOUNT_DIR"
END_MACRO

}

###########################
#
# Create Skeleton
#
# Creates a skeleton of directories to hold data about this account
# 
create_skeleton() {
  ACCOUNT="$1"
  DESTINATION_DIR="$2"

  source <(
    vars_macro "$ACCOUNT" "$DESTINATION_DIR"
  )

  ui_print_note "Creating skeleton at directory $ACCOUNT_DIR..."

  # Root
  mkdir --parents "$ACCOUNT_DIR"

  # Varnish
  mkdir --parents "$ACCOUNT_DIR"/varnish/"$ACCOUNT"/
  touch "$ACCOUNT_DIR"/varnish/"$ACCOUNT"/index.vcl

  # HTTPD
  mkdir --parents "$ACCOUNT_DIR"/httpd/sites/"$ACCOUNT"/
  touch "$ACCOUNT_DIR"/httpd/sites/"$ACCOUNT"/index.conf

  # SRV -- http root
  local dir
  for dir in logs tmp htpasswds notes ftp archives; do
    mkdir --parents "$ACCOUNT_DIR"/srv/"$ACCOUNT"/"$dir"/
  done

  # SSL data
  mkdir --parents "$ACCOUNT_DIR"/tls/certs/"$ACCOUNT"/
  mkdir --parents "$ACCOUNT_DIR"/tls/private/"$ACCOUNT"/

  # MySQL
  mkdir --parents "$ACCOUNT_DIR"/mysql/"$ACCOUNT"/
}

###########################
#
# Gather Resources
#
# Gather all the resources that should be archived for this site.
# 
gather() {
  ACCOUNT="$1"
  DESTINATION_DIR="$2"

  local proceed

  ################
  # Apache
  #
  source <(
    ui_prompt_macro "Gather resources for apache server daemon (conf, docroot, tls)? [Y/n]" proceed y
  )
  if [[ $proceed == "y" ]]; then
    ui_start_task "Gathering resources for apache"
    gather_apache "$ACCOUNT" "$DESTINATION_DIR"
    ui_end_task "Gathering resources for apache"
  fi

  ################
  # Varnish
  #
  source <(
    ui_prompt_macro "Gather resources for varnish server daemon (conf)? [Y/n]" proceed y
  )
  if [[ $proceed == "y" ]]; then
    ui_start_task "Gathering resources for varnish"
    gather_varnish "$ACCOUNT" "$DESTINATION_DIR"
    ui_end_task "Gathering resources for varnish"
  fi

  ################
  # mysql
  #
  source <(
    ui_prompt_macro "Gather resources for mysql (databases)? [Y/n]" proceed y
  )
  if [[ $proceed == "y" ]]; then
    ui_start_task "Gathering resources for mysql"
    gather_mysql "$ACCOUNT" "$DESTINATION_DIR"
    ui_end_task "Gathering resources for mysql"
  fi

  ################
  # logs
  #
  source <(
    ui_prompt_macro "Gather log files? [Y/n]" proceed y
  )
  if [[ $proceed == "y" ]]; then
    ui_start_task "Gathering log files"
    gather_mysql "$ACCOUNT" "$DESTINATION_DIR"
    ui_end_task "Gathering log files"
  fi

}

###########################
#
# Gather Apache Resources
#
# Gather configuration, documents
# 
gather_apache() {
  ACCOUNT="$1"
  DESTINATION_DIR="$2"

  source <(
    vars_macro "$ACCOUNT" "$DESTINATION_DIR"
  )

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
  if [[ -z APACHE_ROOT ]]; then
    source <(
      ui_prompt_macro "Enter root of apache system? (system root is default) [/]" APACHE_ROOT "/"
    )
  fi

  ###########################
  #
  # Gather documents
  # 

  # Use root we decided on
  pushd "$APACHE_ROOT"

  # Document Root
  # Copy contents of main directory over
  cp -rf srv/"$ACCOUNT" "$DESTINATION_DIR"/srv/

  # Apache Configuration
  # 
  # Search for config

  # Look for expected folder for httpd account
  if [[ -d etc/httpd/sites/"$ACCOUNT" ]]; then
    # Directory exists
    ui_print_note "Found expected apache config."
  else
    ui_print_note "Could not find standard folder. You will have to gather apache config yourself."
    ui_print_note "Creating folder $APACHE_ROOT/etc/httpd/sites/$ACCOUNT"
    mkdir --parents etc/httpd/sites/$ACCOUNT

    # TODO: best effort: search and interactively confirm
    ui_print_note "Hit Ctrl-Z, and put desired files into folder $APACHE_ROOT/etc/httpd/sites/$ACCOUNT. Then hit enter to continue."
    ui_press_any_key
  fi

  ui_print_note "Copying files..."
  cp -vrf etc/httpd/sites/"$ACCOUNT"/ "$ACCOUNT_DIR"/httpd/sites/

  # Copy SSL certs, csr's, and keys
  # Look for expected folder for SSL stuff
  if [[ -d etc/pki/tls/certs/"$ACCOUNT" && etc/pki/tls/private/"$ACCOUNT" ]]; then
    # Directory exists
    ui_print_note "Found expected SSL files."
  else
    ui_print_note "Expected account folders were missing. You will have to gather apache config yourself."
    ui_print_note "Creating folder $APACHE_ROOT/etc/httpd/sites/$ACCOUNT"
    mkdir --parents etc/pki/tls/certs/"$ACCOUNT"
    mkdir --parents etc/pki/tls/private/"$ACCOUNT"

    # TODO: best effort: search and interactively confirm
    ui_print_note "Hit Ctrl-Z, and put desired files into folder $APACHE_ROOT/etc/httpd/sites/$ACCOUNT. Then hit enter to continue."
    ui_press_any_key
  fi

  # Copy the files
  ui_print_note "Copying files..."
  cp -vrf /etc/pki/tls/certs/"$ACCOUNT" $ACCOUNT_DIR/tls/certs/"$ACCOUNT"/
  cp -vrf /etc/pki/tls/private/"$ACCOUNT" $ACCOUNT_DIR/tls/private/"$ACCOUNT"/

  # End of apache section
  popd
}


###########################
#
# Gather Varnish Resources
#
# Gather configuration for Varnish
# 
gather_varnish() {
  ACCOUNT="$1"
  DESTINATION_DIR="$2"

  source <(
    vars_macro "$ACCOUNT" "$DESTINATION_DIR"
  )

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
      VARNISH_ROOT="/chroot/varnish"
      ui_print_note "OK, using $VARNISH_ROOT"
    fi
  fi

  # If no varnish root yet, default to system root
  if [[ -z VARNISH_ROOT ]]; then
    source <(
      ui_prompt_macro "Enter root of varnish system? (system root is default) [/]" VARNISH_ROOT "/"
    )
  fi

  ###########################
  #
  # Gather configuration
  # 

  # Use root we decided on
  pushd "$VARNISH_ROOT"

  # Varnish Configuration
  # 
  # Search for config

  # Look for expected folder for varnish account
  if [[ -d etc/varnish/sites/"$ACCOUNT" ]]; then
    # Directory exists
    ui_print_note "Found expected varnish config directory."
  else
    ui_print_note "Could not find standard folder. You will have to gather varnish config yourself."
    ui_print_note "Creating folder $VARNISH_ROOT/etc/varnish/sites/$ACCOUNT"
    mkdir --parents etc/varnish/sites/$ACCOUNT

    # TODO: best effort: search and interactively confirm
    ui_print_note "Hit Ctrl-Z, and put desired files into folder $VARNISH_ROOT/etc/varnish/sites/$ACCOUNT. Then hit enter to continue."
    ui_press_any_key
  fi

  ui_print_note "Copying files..."
  cp -vrf etc/varnish/"$ACCOUNT"/ "$ACCOUNT_DIR"/varnish/

  # End of varnish section
  popd
}


###########################
#
# Gather MySQL Resources
#
# Gather databases for mysql.
# 
gather_mysql() {
  # TODO: dump mysql tables, copy over varnish configuration
  #### Dump and save mysql tables
  # Use chroot if available
  #### if [[ -e /chroot/mysql ]]; then
  ####   pushd /chroot/mysql
  #### else
  ####   pushd /
  #### fi
  #### chroot . mysqldump -u root -p --skip-lock-tables smf > ~-/$ACCOUNT-account/mysql/smf.sql
  #### popd
  local CHROOT=""
  if [[ -e /chroot/mysql ]]; then
    CHROOT="chroot /chroot/mysql"
  fi

  echo "Please dump mysql and hit enter when you return"
  echo "To show databases use something like: \n    echo 'SHOW DATABASES;' | $CHROOT_CMD mysql -B -u root -p"
  echo "To dump databases use something like: \n    $CHROOT_CMD mysqldump -u root -p --skip-lock-tables ${ACCOUNT}_wordpress > $ACCOUNT_DIR/mysql/${ACCOUNT}_wordpress.sql"
  read proceed

  # Check if any files were added
  if [[ -z "$(ls -d $ACCOUNT_DIR/mysql)" ]]; then
    ui_print_note "WARNING! mysql directory is empty. No databases will be created. Strike enter to really continue."
    ui_press_any_key
  fi
}

###########################
#
# Gather logs
#
# TODO: consider rolling into gather_apache
# 
gather_logs() {
  # TODO: still need to gather logs, in case it's in /var/log/apache or /var/log/httpd
  ui_print_note "Please gather log files..."
  ui_press_any_key
}


###########################
#
# Package Account Folder
#
# Package the account: tar, compress, encrypt
# 
package() {
  ACCOUNT="$1"
  DESTINATION_DIR="$2"
  ENCRYPTION_KEY="$3"

  source <(
    vars_macro "$ACCOUNT" "$DESTINATION_DIR"
  )

  local proceed

  source <(
    ui_prompt_macro "Package / encrypt account? [y/N]" proceed n
  )

  if [[ $proceed != "y" ]]; then

    ui_print_note "OK, skipping..."

  else

    # Compress and encrypt the directory
    ui_print_note "Compressing the directory..."
    tar c $ACCOUNT_DIR > $ACCOUNT_DIR.tar
    xz -c $ACCOUNT_DIR.tar | $LIMIT_CMD > $ACCOUNT_DIR.tar.xz
    ui_print_note "Encrypting the archive..."
    cat ACCOUNT_DIR.tar.xz | gpg --symmetric --batch --passphrase="$ENCRYPTION_KEY" \
      | $LIMIT_CMD > ACCOUNT_DIR.tar.xz.gpg

    # TODO: Clean up extra files we generated. Confirm first!
    # 
    #rm -rf "$ACCOUNT"-account{.tar{.xz,},/}

    ui_print_note "Account tarball generated. Saved to:"
    ui_print_list "    $ACCOUNT_DIR.tar.xz"

  fi
}

###########################
#
# Body
# 
# Execute main function
main "$@"

