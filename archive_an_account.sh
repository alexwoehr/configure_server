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

# TODO section below
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
# Packaging:
# - [ ] warn if any gpg files exist in the account directory
# - [ ] no options regarding clobbering

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
LIMIT_CMD_BASE="pv --quiet --rate-limit "
LIMIT_CMD_SLOW="$LIMIT_CMD_BASE 1M"
LIMIT_CMD_FAST="$LIMIT_CMD_BASE 10M"

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
  # Script Parameters: currently ACCOUNT, DESTINATION_DIR, and ENCRYPTION KEY
  source <(
    verify_options_macro "$@"
  )

  ########################
  # Mode for Conflict Resolution
  ui_section "Setup Options: Resolution of Conflicts"

  ui_print_note "There are three possible options for handling conflicts:"

  ui_print_list <<-END_LIST
	safe: do not create a resource at all if it conflicts with an existing archive or resource.
	confirm: confirm what to do
	add: only merge directories or add new files, do not overwrite any files. When in doubt, this functions like safe.
	merge: any existing files are simply overwritten. However, when merging directories, files omitted from the new archive are not deleted.
	clean: remove any existing resources cleanly before installing new resource.
	END_LIST

  source <(
    ui_prompt_macro "Which conflict mode? [safe]" CONFLICT_MODE safe
  )
  if [[ $CONFLICT_MODE == "y" ]]; then
    CONFLICT_MODE="safe"
  fi

  ########################
  # Create skeleton for the account
  ui_section "Create Skeleton"
  source <(
    ui_prompt_macro "Create skeleton for the account? [y/N]" proceed n
  )
  if [[ $proceed != "y" ]]; then
    ui_print_note "OK, skipping..."
  else
    create_skeleton "$ACCOUNT" "$DESTINATION_DIR" "$CONFLICT_MODE"
  fi

  ########################
  # Gather the bits and pieces of this account
  ui_section "Gather resources"
  source <(
    ui_prompt_macro "Gather resources for this account? [y/N]" proceed n
  )
  if [[ $proceed != "y" ]]; then
    ui_print_note "OK, skipping..."
  else
    gather "$ACCOUNT" "$DESTINATION_DIR" "$CONFLICT_MODE"
  fi

  ########################
  # Package up the data
  ui_section "Package up the account"
  source <(
    ui_prompt_macro "Package the account? [y/N]" proceed n
  )
  if [[ $proceed != "y" ]]; then
    ui_print_note "OK, skipping..."
  else
    package "$ACCOUNT" "$DESTINATION_DIR" "$ENCRYPTION_KEY" "$CONFLICT_MODE"
  fi

  # TODO: conclusion
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
  local ACCOUNT="$1"
  local DESTINATION_DIR="$2"
  local CONFLICT_MODE="$3"

  source <(
    vars_macro "$ACCOUNT" "$DESTINATION_DIR"
  )

  ui_print_note "Creating skeleton at directory $ACCOUNT_DIR..."

  # Abstract mkdir with the following function, in order to implement conflict resolution
  create_skeleton_dir() {
    local CONFLICT_MODE="$1"
    local DIR="$2"

    ui_print_note "Creating $DIR..."

    if [[ ! -e $DIR ]]; then
      # Normal case
      mkdir --parents "$DIR"
    else
      # Need to resolve conflict
      # Alert user
      if [[ $CONFLICT_MODE == "safe" ]]; then
        ui_print_note "Warning: Conflict detected! Could not create directory due to conflict: $DIR"
      elif [[ $CONFLICT_MODE == "confirm" ]]; then
        local CONFLICT_DECISION
        ui_print_note "Warning: Conflict detected! $DIR already exists!"
        ui_print_note "CONFIRM MODE. Please confirm how you would like to handle this conflict."
        ui_print_list <<-END_LIST
		skip: Take no other action.
		clean: Remove the existing directory before proceeding.
	END_LIST
        source <(
          ui_prompt_macro "Please specify how to handle" CONFLICT_DECISION "skip"
        )

        if [[ $CONFLICT_DECISION == "y" || $CONFLICT_DECISION == "skip" ]]; then
          exit 1
        elif [[ $CONFLICT_DECISION == "clean" ]]; then
          # Remove the directory
	  rm -rf --one-file-system "$DIR"
	  mkdir --parents "$DIR"
        fi

      elif [[ $CONFLICT_MODE == "add" || $CONFLICT_MODE == "merge" ]]; then

        ui_print_note "Notice: Conflict detected! $DIR already exists."
        ui_print_note "Using conflict resolution strategy '$CONFLICT_MODE'"
	mkdir --parents "$DIR"
	
      elif [[ $CONFLICT_MODE == "clean" ]]; then

        ui_print_note "Notice: Conflict detected! $DIR already exists."
        ui_print_note "Using conflict resolution strategy '$CONFLICT_MODE'"
	ui_print_note "Removing old directory and recreating it..."
	rm -rf --one-file-system "$DIR"
	mkdir --parents "$DIR"
	
      fi
    fi
  }

  # Root
  create_skeleton_dir "$ACCOUNT_DIR"

  # Varnish
  create_skeleton_dir "$ACCOUNT_DIR"/varnish/"$ACCOUNT"/
  touch "$ACCOUNT_DIR"/varnish/"$ACCOUNT"/index.vcl

  # HTTPD
  create_skeleton_dir "$ACCOUNT_DIR"/httpd/sites/"$ACCOUNT"/
  touch "$ACCOUNT_DIR"/httpd/sites/"$ACCOUNT"/index.conf

  # SRV -- http root
  local dir
  for dir in logs tmp htpasswds notes ftp archives; do
    create_skeleton_dir "$ACCOUNT_DIR"/srv/"$ACCOUNT"/"$dir"/
  done

  # SSL data
  create_skeleton_dir "$ACCOUNT_DIR"/tls/certs/"$ACCOUNT"/
  create_skeleton_dir "$ACCOUNT_DIR"/tls/private/"$ACCOUNT"/

  # MySQL
  create_skeleton_dir "$ACCOUNT_DIR"/mysql/"$ACCOUNT"/
}

###########################
#
# Gather Resources
#
# Gather all the resources that should be archived for this site.
# 
gather() {
  local ACCOUNT="$1"
  local CONFLICT_MODE="$2"

  local proceed

  ################
  # Apache
  #
  source <(
    ui_prompt_macro "Gather resources for apache server daemon (conf, docroot, tls)? [Y/n]" proceed y
  )
  if [[ $proceed == "y" ]]; then
    ui_start_task "Gathering resources for apache"
    gather_apache "$ACCOUNT" "$DESTINATION_DIR" "$CONFLICT_MODE"
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
    gather_varnish "$ACCOUNT" "$DESTINATION_DIR" "$CONFLICT_MODE"
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
    gather_mysql "$ACCOUNT" "$DESTINATION_DIR" "$CONFLICT_MODE"
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
    gather_logs "$ACCOUNT" "$DESTINATION_DIR" "$CONFLICT_MODE"
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
  CONFLICT_MODE="$3"

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
      APACHE_ROOT="/chroot/apache"
    fi
  fi

  # If no apache root yet, default to system root
  if [[ -z $APACHE_ROOT ]]; then
    source <(
      ui_prompt_macro "Enter root of apache system? (system root is default) [/]" APACHE_ROOT "/"
    )
  fi

  ui_print_note "Using apache chroot: $APACHE_ROOT"

  ###########################
  #
  # Gather documents
  # 

  # Use root we decided on
  pushd "$APACHE_ROOT"

  # Document Root
  # Copy contents of main directory over
  ui_print_note "Gathering document root: contents of /srv directory"
  cp -rf srv/"$ACCOUNT"/ "$ACCOUNT_DIR"/srv/.

  # Apache Configuration
  # 
  # Search for config

  # Look for expected folder for httpd account
  ui_print_note "Gathering apache configuration (/etc/httpd)"
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

  ui_print_note "Copying conf directories..."
  cp -vrf etc/httpd/sites/"$ACCOUNT"/ "$ACCOUNT_DIR"/httpd/sites/.

  # Copy SSL certs, csr's, and keys
  # Look for expected folder for SSL stuff
  ui_print_note "Gathering SSL configuration (/etc/pki/tls)"
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
  ui_print_note "Copying tls files..."
  cp -vrf /etc/pki/tls/certs/"$ACCOUNT"/ $ACCOUNT_DIR/tls/certs/.
  cp -vrf /etc/pki/tls/private/"$ACCOUNT"/ $ACCOUNT_DIR/tls/private/.

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
  CONFLICT_MODE="$3"

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
  cp -vrf etc/varnish/"$ACCOUNT"/ "$ACCOUNT_DIR"/varnish/.

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
  ACCOUNT="$1"
  DESTINATION_DIR="$2"
  CONFLICT_MODE="$3"

  source <(
    vars_macro "$ACCOUNT" "$DESTINATION_DIR"
  )

  local proceed

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
  local CHROOT_CMD=""

  if [[ -e /chroot/mysql ]]; then
    CHROOT_CMD="chroot /chroot/mysql"
  fi

  echo "Please dump mysql and hit enter when you return"
  echo "To show databases use something like: \n    echo 'SHOW DATABASES;' | $CHROOT_CMD mysql -B -u root -p"
  echo "To dump databases use something like: \n    $CHROOT_CMD mysqldump -u root -p --skip-lock-tables ${ACCOUNT}_wordpress > $ACCOUNT_DIR/mysql/${ACCOUNT}_wordpress.sql"
  read proceed

  # Check if any files were added
  if [[ -z "$(ls -d "$ACCOUNT_DIR"/mysql)" ]]; then
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
  # Variables
  #
  # Parameters
  ACCOUNT="$1"
  DESTINATION_DIR="$2"
  ENCRYPTION_KEY="$3"
  CONFLICT_MODE="$4"

  source <(
    vars_macro "$ACCOUNT" "$DESTINATION_DIR"
  )

  # Function to help us resolve file conflicts
  #
  # Resolve conflicts for individual files
  package_resolve_conflict() {
    local CONFLICT_MODE="$1"
    local FILE="$2"
    local CMD="$3"
    local proceed

    if [[ ! -e $FILE ]]; then
      eval "$CMD"
    else
      # Need to resolve conflict
      if [[ $CONFLICT_MODE == "safe" || $CONFLICT_MODE == "add" ]]; then
	ui_print_note "Warning: Conflict detected! Could not create directory due to conflict: $DIR"
	# do nothing
      elif [[ $CONFLICT_MODE == "confirm" ]]; then
	local CONFLICT_DECISION
	ui_print_note "Warning: Conflict detected! file '$FILE' already exists!"
	ui_print_note "CONFIRM MODE. Please confirm how you would like to handle this conflict."
	ui_print_list <<-END_LIST
		skip: Take no other action. Skip to next step, using current file.
		clean: Remove the existing file before proceeding.
	END_LIST
	local CONFLICT_DECISION
	source <(
	  ui_prompt_macro "Please specify how to resolve the conflict." CONFLICT_DECISION "skip"
	)

	if [[ $CONFLICT_DECISION == "y" || $CONFLICT_DECISION == "skip" ]]; then
	  exit 1
	elif [[ $CONFLICT_DECISION == "clean" ]]; then
	  # Remove the directory
	  rm -rf --one-file-system "$FILE"
	  eval "$CMD"
	fi

      elif [[ $CONFLICT_MODE == "merge" || $CONFLICT_MODE == "clean" ]]; then

	ui_print_note "Notice: Conflict detected! $FILE already exists."
	ui_print_note "Using conflict resolution strategy '$CONFLICT_MODE' to create file."
	rm -rf --one-file-system "$FILE"
	eval "$CMD"

      fi
    fi
  }

  local proceed

  source <(
    ui_prompt_macro "Package / encrypt account? [y/N]" proceed n
  )

  if [[ $proceed != "y" ]]; then

    ui_print_note "OK, skipping..."

  else

    # Compress and encrypt the entire account directory
    ui_print_note "Creating the directory archive file..."
    local TAR_CMD="tar c '$ACCOUNT_DIR' \
      | $LIMIT_CMD_FAST \
      > '$ACCOUNT_DIR.tar'
    "

    # Execute command
    package_resolve_conflict "$CONFLICT_MODE" "$ACCOUNT_DIR.tar" "$TAR_CMD"

    # Determine whether to do a full archive or incremental
    source <(
      ui_prompt_macro "Generate incremental archive from previous version? [y/N]" proceed n
    )

    local compress_file
    if [[ $proceed != "y" ]]; then
      ui_print_note "OK, generating full backup..."
      compress_file="$ACCOUNT_DIR.tar"
    else
      ui_print_note "Generating rdiff incremental patchfile..."
      local OLD_ARCHIVE
      source <(
        ui_prompt_macro "Please enter the path of the old archive or its signature." OLD_ARCHIVE n
      )

      # Strip off sig if that's all they have
      # If they gave us a sig already, we'll skip the generation of sigs.
      OLD_ARCHIVE="${OLD_ARCHIVE%.sig}"

      # TODO: handle dependencies a LOT more gracefully
      ui_print_note "Installing dependencies as necessary..."
      yum --assumeyes --enablerepo=epel install rdiff-backup

      # If sig exists already, skip generation
      # Of course, as it stands, this overrides conflict resolution mode.
      local RDIFF_CMD
      if [[ ! -e $OLD_ARCHIVE.sig ]]; then
        ui_print_note "Generating rdiff signatures..."
        local RDIFF_CMD="rdiff signature \
          '$OLD_ARCHIVE' \
          '$OLD_ARCHIVE.sig'
	"
	package_resolve_conflict "$CONFLICT_MODE" "$OLD_ARCHIVE.sig" "$RDIFF_CMD"
      fi

      ui_print_note "Generating rdiff delta..."

      RDIFF_CMD="rdiff delta \
	$OLD_ARCHIVE.sig \
	$ACCOUNT_DIR.tar \
	$ACCOUNT_DIR.tar.delta
      "
      package_resolve_conflict "$CONFLICT_MODE" "$ACCOUNT_DIR.tar.delta" "$RDIFF_CMD"

      compress_file="$ACCOUNT_DIR.tar.delta"
    fi

    ui_print_note "Compressing the archive..."
    local XZ_CMD="xz -c '$compress_file' \
      | $LIMIT_CMD_SLOW \
      > '$compress_file.xz'
    "

    package_resolve_conflict "$CONFLICT_MODE" "$compress_file.xz" "$XZ_CMD"

    ui_print_note "Encrypting the archive..."
    local GPG_CMD="cat '$compress_file.xz' \
        | gpg --symmetric --batch --passphrase="$ENCRYPTION_KEY" \
        | $LIMIT_CMD_FAST \
        > '$compress_file.xz.gpg'
    "

    package_resolve_conflict "$CONFLICT_MODE" "$compress_file.xz.gpg" "$GPG_CMD"

    # TODO: Clean up extra files we generated. Confirm first!
    # - Could depend on conflict resolution mode...dunno
    # 
    #rm -rf "$ACCOUNT"-account{.tar{.xz,},/}

    ui_print_note "Account archive generated. Saved to:"
    ui_print_list <<<"    $compress_file.xz.gpg"

  fi
}

###########################
#
# Body
#
# Execute main function
main "$@"

