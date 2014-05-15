
function acknowledge_data() {
  echo "-- press any key to continue --"
  read proceed
}

function display_welcome_banner() {
  echo 
  echo "=============================="
  echo "== WELCOME TO ${1##*/}"
  echo "=============================="
  echo
}

function dump_runtime_variables() {
  echo "------------------------------"
  echo "-- Runtime Global Variables"
  echo "------------------------------"
  echo "- (see setup_vars.sh for definition)"
  echo PARTITIONS "$PARTITIONS"
  echo UNDO_FILE "$UNDO_FILE"
  echo TMP_DIR "$TMP_DIR"
  echo LIB_DIR "$LIB_DIR"
  echo SCRATCH "$SCRATCH"
  echo ACTIONS_COUNTER "$ACTIONS_COUNTER"
  echo ACTIONS_TAKEN_FILE "$ACTIONS_TAKEN_FILE"
  acknowledge_data();
}

