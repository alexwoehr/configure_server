
# Function: ui_press_any_key
# Description: Confirm from user that it's okay to proceed
# 
ui_press_any_key() {
  echo ">>> press enter to continue <<<"
  local proceed
  read proceed
}

# Function: ui_section
# Description: announce a new section to the user. Request clearance to proceed.
# 
ui_section() {
  local title="$1"
  echo
  echo "======================="
  echo "=="
  echo "== $title"
  echo "=="
  echo "======================="
  echo

  ui_press_any_key
}

ui_start_task() {
  local title="$1"
  echo "----------------------------------------------"
  echo "... Begin: $title ..."

  ui_press_any_key
}

ui_end_task() {
  local title="$1"
  echo "... Done: $title."

  ui_press_any_key
}

# Function: ui_escape_output
# Description: Escape output with descriptive initial header

ui_escape_output() {
  # Pipe stdin into sed and prepend escape
  local cmd="$1"
  cat | sed "s/^/[$cmd says] /"
}

# Function: ui_print_note
# Description: Display a conclusion

ui_print_note() {
  local note="$1"
  echo "--- $note"
}

# Function: ui_print_list
# Description: Format a stream (separated by linebreaks) into a list of items

ui_print_list() {
  sed 's/^/- /' -- "$@"
}

# Function: ui_proceed
# Description: Offer choices

ui_proceed() {
  local choice;
  local task="$1"
  local default_choice="$2"
  echo ">>> Proceed with task: $task? y/n [$default_choice]"
  read choice
  if [[ -z $proceed ]]; then
    # Use default if no choice supplied
    $choice=$default_choice
  fi
  echo "<<< OK, you said $choice"
}

# ui_prompt_macro:
#   Standard ui function to prompt for an input.
# 
# hold onto your hats, this is a macro
# Run it like this:
#   source <( ui_prompt_macro "prompt" "inputVar" "default"  )
ui_prompt_macro() {
  # Variables
  local prompt="$1"
  local varname="$2"
  local default_value="$3"
  # Note: is expansion safe?
  # Create macro and replace arguments
  cat - <<-END_MACRO
        echo ">>>" "$prompt"
        read "$varname"
        # Substitute default value if necessary
        $varname=\${$varname:-$default_value}
        echo "<<< OK, you said \$$varname"
END_MACRO

}

# Generic read function
# Slimmed down version of ui_prompt_macro
ui_read_macro() {

  cat - <<-END_MACRO
        read "$1"
END_MACRO

}

# Uses grep to highlight
ui_highlight() {
  local expression="$1"
  shift
  cat - \
  | grep --color=always --regexp="$expression" "$@"
}

