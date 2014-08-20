#!/bin/bash

# Utility functions for working with streams
intersect() {
  comm -12 - "$@"
}

difference() {
  comm -23 - "$@"
}

union() {
  cat - "$@" | sort
}

# System functions
# 
# Check if selinux is enabled
fn_selinux_enabled() {
  if [ 0 '<' $( getenforce | grep "Disabled" | wc -l) ]; then
    # Disabled
    return 1
  else
    # Enforcing or Permissive
    return 0
  fi
}

# Get login for a user
fn_get_user_login() {
  local acct="$1"
  cat /etc/passwd \
  | awk -F: "\$1 == \"$acct\" {print \$NF}"
}

# Functions for listing different kinds of users
# 
# Get system users (not including root)
fn_parse_system_users() {
  cat /etc/passwd \
  | grep --invert-match ^root: \
  | awk --field-separator=":" '$3 < 500' 
}

# List accounts that should definitely be locked
# Get FTP users
fn_parse_ftp_users() {
  cat /etc/passwd \
  | awk --field-separator=":" 'substr($1, 1, 3) == "ftp"' 
}

# List users set to "nologin"
fn_parse_nologin_users() {
  cat /etc/passwd \
  | awk --field-separator=":" '$NF == "/sbin/nologin"'
}

# List system processes that use their own name as login shell
fn_parse_narcissist_users() {
  cat /etc/passwd \
  | awk --field-separator=":" '$1 == substr($NF, length($NF) - length($1) + 1)'
}

# List users with locked password (preceded by "!")
fn_parse_locked_users() {
  cat /etc/shadow \
  | awk --field-separator=":" 'substr($2, 1, 1) == "!"'
}

# Macros and helper functions for setup script
# 
# Note: if you submit a callback, you must be prepared to set it.
fn_backup_config_file_macro() {
  local modfile="$1"
  local callback_name="$2"

  # Save old file
  local modfile_old_bak="$modfile".save-before-`date +%F`
  if [ ! -e "$modfilebak" ]; then
    cp $modfile $modfile_old_bak
  fi

  # Return 
  if [[ -n "$callback_name" ]]; then
    local modfile_new_bak="$modfile".save-after-`date +%F`
    # Send it on standard out
    cat - <<-END_MACRO
      $callback_name() {
        cp "$modfile" "$modfile_new_bak"
      }
END_MACRO
  fi
}

