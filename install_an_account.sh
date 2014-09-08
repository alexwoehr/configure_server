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
  # Unpack the file
  source <(
    ui_prompt_macro "Unpack the account file? [y/N]" proceed n
  )
  if [[ $proceed != "y" ]]; then
    ui_print_note "OK, skipping..."
  else
    ui_start_task "Unpacking"
    unpack_archive "$ACCOUNT_PKG" "$ENCRYPTION_KEY" "$CONFLICT_MODE"
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
    install_archive "$ACCOUNT_PKG" "$CONFLICT_MODE"
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
    ACCOUNT_PKG="$ACCOUNT_PKG"
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
  # Remove suffix, if it's there
  local ACCOUNT="${ACCOUNT%-account}";

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
  # Variables
  local ACCOUNT_PKG="$1"
  local ENCRYPTION_KEY="$2"
  local CONFLICT_MODE="$3"

  source <(
    vars_macro "$ACCOUNT_PKG"
  )

  ####
  # 
  # Function to help us resolve file conflicts
  #
  # Resolve conflicts for individual files
  unpack_archive_resolve_conflict() {
    local CONFLICT_MODE="$1"
    local FILE="$2"
    local CMD="$3"
    local proceed

    if [[ ! -e $FILE ]]; then
      eval "$CMD"
    else
      # File already exists.
      # 
      # Need to resolve conflict
      if [[ $CONFLICT_MODE == "safe" || $CONFLICT_MODE == "add" ]]; then
	ui_print_note "Warning: Conflict detected! Could not create directory due to conflict: $FILE"
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


  # Decrypt
  ui_print_note "Decrypting file $ACCOUNT_PKG..."

  # After decryption, loses the .gpg extension
  local decrypted_file="${ACCOUNT_PKG%.gpg}"
  local GPG_CMD="cat '$ACCOUNT_PKG' \
    | gpg --batch --decrypt --passphrase='$ENCRYPTION_KEY' \
    | $LIMIT_CMD \
    > '$decrypted_file'
  "

  # Run command
  unpack_archive_resolve_conflict "$CONFLICT_MODE" "$GPG_CMD" "$decrypted_file"
  
  ui_print_note "OK, decrypted file."
  ui_print_note "Decompressing file $decrypted_file..."

  # After decompression, loses the .xz extension
  local decompressed_file="${decrypted_file%.xz}"
  UNXZ_CMD="unxz -c '$decrypted_file' \
    | $LIMIT_CMD \
    > '$decompressed_file'
  "

  unpack_archive_resolve_conflict "$CONFLICT_MODE" "$UNXZ_CMD" "$decompressed_file"

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

    ui_start_task "Patching based on deltas..."

    local RDIFF_CMD="rdiff patch \
      '$OLD_ARCHIVE' \
      '$decompressed_file' \
      '$ACCOUNT_DIR.tar'
    "

    unpack_archive_resolve_conflict "$CONFLICT_MODE" "$RDIFF_CMD" "$ACCOUNT_DIR.tar"

    ui_end_task "Patching based on deltas..."

  fi

  # Either way, previous branch must end with a $ACCOUNT_DIR.tar file.

  # Expand tar archive into directory
  ui_print_note "Expanding into the account directory..."
  pushd "$SOURCE_DIR"
  local TAR_CMD="tar xf '$ACCOUNT_DIR.tar'"
  unpack_archive_resolve_conflict "$CONFLICT_MODE" "$TAR_CMD" "$ACCOUNT_DIR"
  popd "$SOURCE_DIR"

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
  local CONFLICT_MODE="$2"
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
    install_archive_apache "$ACCOUNT_PKG" "$CONFLICT_MODE"
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
    install_archive_varnish "$ACCOUNT_PKG" "$CONFLICT_MODE"
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
    install_archive_mysql "$ACCOUNT_PKG" "$CONFLICT_MODE"
    ui_end_task "Installing resources for mysql"
  fi

}

###########################
#
# Install apache resources for this account
#
install_archive_apache() {
  local ACCOUNT_PKG="$1"
  local CONFLICT_MODE="$2"

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

  # Currently conflict resolution is based on directories; interactive confirm per file is not supported.
  # TODO: could support interactive.

  # Install into apache's docroot
  local CP_CMD="cp -r '$ACCOUNT_DIR'/srv/'$ACCOUNT'/* srv/'$ACCOUNT'/."
  install_archive_resolve_conflict "$CONFLICT_MODE" "$CP_CMD" srv/"$ACCOUNT"/.

  # Install configuration
  mkdir --parents etc/httpd/"$ACCOUNT"/
  CP_CMD="cp -rv '$ACCOUNT_DIR'/httpd/sites/$ACCOUNT/* etc/httpd/sites/'$ACCOUNT'/."
  install_archive_resolve_conflict "$CONFLICT_MODE" "$CP_CMD" etc/httpd/sites/"$ACCOUNT"/.

  mkdir --parents etc/pki/tls/certs/"$ACCOUNT"/
  CP_CMD="cp -rv '$ACCOUNT_DIR'/tls/certs/'$ACCOUNT'/* etc/pki/tls/certs/'$ACCOUNT'/."
  install_archive_resolve_conflict "$CONFLICT_MODE" "$CP_CMD" etc/pki/tls/certs/"$ACCOUNT"/.

  mkdir --parents etc/pki/tls/private/"$ACCOUNT"/
  CP_CMD="cp -rv '$ACCOUNT_DIR'/tls/private/'$ACCOUNT'/* etc/pki/tls/private/'$ACCOUNT'/."
  install_archive_resolve_conflict "$CONFLICT_MODE" "$CP_CMD" etc/pki/tls/private/"$ACCOUNT"/

  # Leave apache chroot
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

  pushd "$VARNISH_ROOT"

  mkdir --parents etc/varnish/"$ACCOUNT"/.
  CP_CMD="cp -rv '$ACCOUNT_DIR'/varnish/* etc/varnish/'$ACCOUNT'/."
  install_archive_resolve_conflict "$CONFLICT_MODE" "$CP_CMD" etc/varnish/"$ACCOUNT"/.

  popd

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

    # Determine how to proceed based on conflict mode.

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

# Helper function: resolve conflicts for installers
# Assumes first character of CMD is a herestring.
install_archive_resolve_conflict() {
  local CONFLICT_MODE="$1"
  local DIR="$2"
  local CMD="$3"
  local proceed

  if [[ ! -e $DIR ]]; then
    eval "$CMD"
  else
    # Need to resolve conflict
    if [[ $CONFLICT_MODE == "safe" ]]; then
      ui_print_note "Warning: Conflict detected! Could not create directory due to conflict: $DIR"
      # do nothing
    elif [[ $CONFLICT_MODE == "confirm" ]]; then
      local CONFLICT_DECISION
      ui_print_note "Warning: Conflict detected! directory '$DIR' already exists!"
      ui_print_note "CONFIRM MODE. Please confirm how you would like to handle this conflict."
      ui_print_list <<-END_LIST
		skip: Take no other action. Skip to next step, using current directory.
		add: Add any new files but skip existing files. When in doubt, this behaves like skip.
		merge: Overwrite files, add new files. Files not in the archive are left alone
		clean: Remove the existing directory before proceeding.
	END_LIST
      local CONFLICT_DECISION
      source <(
        ui_prompt_macro "Please specify how to resolve the conflict." CONFLICT_DECISION "skip"
      )

      if [[ $CONFLICT_DECISION == "y" || $CONFLICT_DECISION == "skip" ]]; then
        exit 1
      elif [[ $CONFLICT_DECISION == "add" ]]; then
        # Copy files in, but instruct CP not to clobber
        # We have to do some surgery on cp...this isn't really safe. <<< is a here-string.
        CMD="$(
          <<<"$CMD" sed 's/^cp /cp --no-clobber /'
        )"
        eval "$CMD"
      elif [[ $CONFLICT_DECISION == "merge" ]]; then
        # Copy files in. Instruct CP to clobber
        # We have to do some surgery on cp...this isn't really safe. <<< is a here-string.
        CMD="$(
          <<<"$CMD" sed 's/^cp /cp --force /'
        )"
        eval "$CMD"
      elif [[ $CONFLICT_DECISION == "clean" ]]; then
        # Remove the directory completely first
        rm -rf --one-file-system "$DIR"
        eval "$CMD"
      fi

    elif [[ $CONFLICT_MODE == "add" ]]; then

      ui_print_note "Warning: Conflict detected! directory '$DIR' already exists!"
      ui_print_note "ADD MODE. Adding new files without modifying existing ones."
      # Copy files in, but instruct CP not to clobber
      # We have to do some surgery on cp...this isn't really safe. <<< is a here-string.
      CMD="$(
        <<<"$CMD" sed 's/^cp /cp --no-clobber /'
      )"
      eval "$CMD"

    elif [[ $CONFLICT_MODE == "merge" ]]; then

      ui_print_note "Warning: Conflict detected! directory '$DIR' already exists!"
      ui_print_note "MERGE MODE. Overwriting existing files without removing any files not in the new archive."
      # Copy files in. Instruct CP to clobber
      # We have to do some surgery on cp...this isn't really safe. <<< is a here-string.
      CMD="$(
        <<<"$CMD" sed 's/^cp /cp --force /'
      )"
      eval "$CMD"

    elif [[ $CONFLICT_MODE == "clean" ]]; then

      ui_print_note "Notice: Conflict detected! $DIR already exists."
      ui_print_note "Using conflict resolution strategy '$CONFLICT_MODE' so deleting directory tree before adding new files."
      rm -rf --one-file-system "$DIR"
      eval "$CMD"

    fi
  fi
}

###########################
#
# Body
#
# Execute main function
main "$@"

