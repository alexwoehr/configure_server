
# Check if selinux is disabled
fn_selinux_enabled() {
  if [ -s <( getenforce | grep "Disabled" ) ]; then
    # Disabled
    return 1
  else
    # Enforcing or Permissive
    return 0
  fi
}

