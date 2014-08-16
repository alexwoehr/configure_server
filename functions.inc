
# Check if selinux is disabled
fn_selinux_enabled() {
  if -s <( getenforce | grep "Disabled" ); then
    # Disabled
    exit 1
  else
    # Enforcing or Permissive
    exit 0
  fi
}

