
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
  title="$1" && shift
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
  readonly local title="$1"
  shift
  echo "----------------------------------------------"
  echo "... Begin: $title ..."

  ui_press_any_key
}

ui_end_task() {
  readonly local title="$1"
  shift
  echo "... Done: $title."

  ui_press_any_key
}

# Function: ui_escape_output
# Description: Escape output with descriptive header

ui_escape_output() {
  # Pipe stdin into sed and prepend escape
  readonly local cmd="$1"
  shift
  cat | sed "s/^/[$cmd says] /"
}

# Function: ui_print_note
# Description: Display a conclusion

ui_print_note() {
  readonly local note="$1"
  shift
  echo "--- $note"
}

# Function: ui_proceed
# Description: Offer choices

ui_proceed() {
  local choice;
  task="$1"
  shift
  readonly local default_choice="$1"
  shift
  echo ">>> Proceed with task: $task? y/n [$default_choice]"
  read choice
  if [[ -z $proceed ]]; then
    # Use default if no choice supplied
    $choice=$default_choice
  fi
  echo "<<< OK, using $choice"
}

# hold onto your hats
# this is a macro
# Run it like this:
#   source <( ui_prompt_macro "prompt" "inputVar" "default"  )
ui_prompt_macro() {
  # Variables
  readonly local prompt="$1"
  shift
  readonly local varname="$1"
  shift
  readonly local default_value="$1"
  shift
  # Note: is expansion safe?
  # Create macro and replace arguments
  cat - <<-END_MACRO
        echo ">>>" "$prompt"
        read "$varname"
        # Substitute default value if necessary
        $varname=\${$varname:-$default_value}
        echo "<<< OK, using \$$varname"
END_MACRO

}

# Uses grep to highlight
ui_highlight() {
  local readonly expression="$1"
  shift
  cat - \
  | grep --color=always --regexp="$expression" "$@"
}

