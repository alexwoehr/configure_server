#!/bin/bash

# Check if selinux is enabled
fn_selinux_enabled() {
  if [ -s <( getenforce | grep "Disabled" ) ]; then
    # Disabled
    return 1
  else
    # Enforcing or Permissive
    return 0
  fi
}

# Note: if you submit a callback, you must be prepared to set it.
fn_backup_config_file_macro() {
  local readonly modfile="$1"
  local readonly callback_name="$2"

  # Save old file
  local readonly modfile_old_bak="$modfile".save-before-`date +%F`
  if [ ! -e "$modfilebak" ]; then
    cp $modfile $modfile_old_bak
  fi

  # Return 
  if [[ -n "$callback_name" ]]; then
    local readonly modfile_new_bak="$modfile".save-after-`date +%F`
    # Send it on standard out
    cat - <<-END_MACRO
      $callback_name() {
        cp "$modfile" "$modfile_new_bak"
      }
END_MACRO
  fi
}

