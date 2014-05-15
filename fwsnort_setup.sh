#!/usr/bin/env bash

# Check for installation switch
#
if [[ "$1" == "install" ]]; then
  echo "... Entering installation mode ..."
  echo "======================================"
  echo "Welcome to fwsnort_setup installation!"
  echo "======================================"
  echo "--- press any key to continue ---"
  read proceed

  echo "... Adding file to /var/lib/fwsnort/fwsnort_setup.sh ..."
  if [[ "${0##/*}" != "/var/lib/fwsnort" ]]; then
    mkdir --parents /var/lib/fwsnort
    cp $0 /var/lib/fwsnort/fwsnort_setup.sh
  fi
  echo "... Done"

  if readlink --silent /usr/bin/fwsnort_setup.sh; then
    echo "... Removing pre-existing link ..."
    rm /usr/bin/fwsnort_setup.sh
    echo "... Done"
  fi

  echo "... Linking new script in /usr/bin directory ..."
  ln -s /var/lib/fwsnort/fwsnort_setup.sh /usr/bin/fwsnort_setup.sh
  echo "... Done"
  
  echo "... You should now be able to run fwsnort_setup by executing the following command:"
  echo ">>>>    fwsnort_setup.sh"
  echo "... Exiting installation mode."
  exit 0
fi

# Run this after generating a new version of iptables
TMP_DIR=/tmp/iptables-prep.$$
mkdir --parents $TMP_DIR
SCRATCH="$TMP_DIR"/tmp

echo "Restart iptables? [Y/n]"
read proceed
if [[ "$proceed" == "n" ]]; then
  echo "... OK, iptables restart skipped"
else
  echo "... Restarting ..."
  if [[ -e /etc/sysconfig/flush_iptables.sh ]]; then
    echo "... Found custom iptables restart script, using it instead. ..."
    echo "... Running /etc/sysconfig/flush_iptables.sh ..."
    /etc/sysconfig/flush_iptables.sh
  else
    service iptables restart
  fi
  echo "... Done"
fi

echo "Update fwsnort? [Y/n]"
read proceed
if [[ "$proceed" == "n" ]]; then
  echo "... OK, fwsnort update skipped"
else
  echo "... Updating snort rules ..."
  fwsnort --update-rules | sed 's/.*/[fwsnort says] \0/'
  echo "... Done"
fi

echo "Update start location in fwsnort.conf? [Y/n]"
read proceed
if [[ "$proceed" == "n" ]]; then
  echo "... OK, fwsnort.conf reconfigure skipped"
else
  echo "... Checking iptables rules for manual insert ..."
  # Initialize sed script
  > "$TMP_DIR/fwsnort_conf_update.sed"
  # Tell each chain to start where it is supposed to start
  for CHAIN in INPUT OUTPUT FORWARD; do
    cat /etc/sysconfig/iptables \
    | grep -e "^--append $CHAIN" -e "^-A $CHAIN" -e "#.*INSERT FWSNORT_$CHAIN HERE" \
    | grep --line-number "INSERT FWSNORT_$CHAIN HERE" \
    | cut --fields=1 --delimiter=":" \
    | tr "\n" " " \
      > "$SCRATCH"
    if [[ ! -s "$SCRATCH" ]]; then
      echo "... no manual insert rules specified for $CHAIN, setting as 1 ..."
      CHAIN_START=1
    else
      CHAIN_START=`cat $SCRATCH | tr -d "\n \t"`
    fi
    # Append to update
    >> "$TMP_DIR/fwsnort_conf_update.sed" echo "/FWSNORT_""$CHAIN""_JUMP[ ]*/s/[0-9]*;/$CHAIN_START;/"
  done;
  echo "... updating configuration now ..."
  sed --in-place --file="$TMP_DIR/fwsnort_conf_update.sed" /etc/fwsnort/fwsnort.conf
  echo "... Done"
fi

echo "Generate iptables rules from fwsnort? [Y/n]"
read proceed
if [[ "$proceed" == "n" ]]; then
  echo "... OK, regenerate fwsnort rules skipped"
else
  echo "... Generating iptables ruleset ..."
  fwsnort | sed 's/.*/[fwsnort says] \0/'
  echo "... Done"
fi

echo "Splice in new ruleset? [Y/n]"
read proceed
if [[ "$proceed" == "n" ]]; then
  echo "... OK, fwsnort splice skipped"
else
  echo "... Adding new rules ..."
  /var/lib/fwsnort/fwsnort.sh | sed 's/.*/[fwsnort says] \0/'
  echo "... Done"
fi

echo "All changes completed."

