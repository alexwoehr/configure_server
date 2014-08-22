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
# Get public IP address

public_ip_services="
169.254.169.254/latest/meta-data/public-ipv4
ipecho.net/plain
ip-echo.appspot.com
"

fn_get_public_ip() {
  # load best service
  local public_ip
  if [ -z "$public_ip" ]; then
    # Try amazon first
    public_ip="$(wget --timeout=10 "169.254.169.254/latest/meta-data/public-ipv4")"
    if [ -z "$public_ip" ]; then
      # Try another service
      public_ip="$(wget --timeout=10 wgetip.com)"
      if [ -z "$public_ip" ]; then
        # nothing is working.
        exit 1 # trouble
      fi
    fi
  fi

  echo -n $public_ip
}

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

# Check if a group exists
# Empty if no group, otherwise returns name of group
fn_does_group_exist_yn() {
  local groupName="$1"
  grep "^$groupName:" /etc/group \
  | cut --fields=1 --delimiter=':'
}

# Lists users (additional users) in a group
fn_list_addl_users_in_group() {
  local groupName="$1"
  getent group "$groupName" \
  | awk --field-separator=':' '{print $NF}' \
  | tr ',' "\n"
}

# Functions for listing different kinds of users
# 
# Get system users (not including root)
fn_parse_system_users() {
  cat /etc/passwd \
  | grep --invert-match ^root: \
  | awk --field-separator=":" '$3 < 500 {print $1 }'
}

# List accounts that should definitely be locked
# Get FTP users
fn_parse_ftp_users() {
  cat /etc/passwd \
  | awk --field-separator=":" 'substr($1, 1, 3) == "ftp" {print $1 }' 
}

# List users set to "nologin"
fn_parse_nologin_users() {
  cat /etc/passwd \
  | awk --field-separator=":" '$NF == "/sbin/nologin" { print $1 }'
}

# List system processes that use their own name as login shell
fn_parse_narcissist_users() {
  cat /etc/passwd \
  | awk --field-separator=":" '$1 == substr($NF, length($NF) - length($1) + 1) { print $1 }'
}

# List users with locked password (preceded by "!")
fn_parse_locked_users() {
  cat /etc/shadow \
  | awk --field-separator=":" 'substr($2, 1, 1) == "!" { print $1 }'
}

# Functions for working with pam

# Get stacking behavior (required, requisite, sufficient, etc)
pam_get_stacking() {
  local file="$1"
  local line="$2"
  cat "/etc/pam.d/$file" \
  | awk 'FNR == "'$line'" { print $2 }'
}

# Find line number containing wheel privileges
pam_find_wheel() {
  local file="${1:-su}"
  # Print out the line number for the line we are looking for
  cat "/etc/pam.d/$file" \
  | awk '$1 == "#auth" && $3 == "pam_wheel.so" { print FNR }' \
  | tail -n 1
}

# Find line number involving password quality
pam_find_cracklib() {
  local file="${1:-system-auth}"
  # Cat the line number for the line we are looking for
  cat "/etc/pam.d/$file" \
  | awk '$1 == "password" && $3 == "pam_cracklib.so" { print FNR } ' \
  | head -1
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

