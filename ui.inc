
# Function: ui_press_any_key
# Description: Confirm from user that it's okay to proceed
# 
ui_press_any_key() {
  echo ">>> press any key to continue <<<"
  read proceed
}

# Function: ui_section
# Description: announce a new section to the user. Request clearance to proceed.
# 
ui_section() {
  readonly title="$1" && shift
  echo
  echo "-----------------------"
  echo "--"
  echo "-- $title"
  echo "--"
  echo "-----------------------"
  echo

  ui_press_any_key
}

ui_start_task() {
  readonly title="$1" && shift
  echo "... Begin: $title ..."

  ui_press_any_key
}

ui_end_task() {
  readonly title="$1" && shift
  echo "... Done: $title."

  ui_press_any_key
}

# Function: ui_escape_output
# Description: Escape output with descriptive header

ui_escape_output() {
  # Pipe stdin into sed and prepend escape
  readonly cmd="$1" && shift
  cat | sed "s/^/[$cmd says] /"
}

# Function: ui_print_note
# Description: Display a conclusion

ui_print_note() {
  readonly note="$1" && shift
  echo --- "$note"
}

# Function: ui_proceed
# Description: Offer choices

ui_proceed() {
  local choice;
  readonly task="$1" && shift
  readonly default_choice="$1" && shift
  echo ">>> Proceed with task: $task? y/n [$default_choice]"
  read choice
  if [[ -z $proceed ]]; then
    # Use default if no choice supplied
    $choice=$default_choice
  fi
  echo "<<< OK, using $choice"
}

ui_prompt() {
  local choice;
  readonly prompt="$1" && shift
  readonly options="$1" && shift
  readonly default_choice="$1" && shift
  echo ">>>" "$prompt" "[$options]"
  read choice
  if [[ -z $proceed ]]; then
    # Use default if no choice supplied
    $choice=$default_choice
  fi
  echo "<<< OK, using $choice"
}

