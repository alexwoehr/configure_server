#!/bin/sh

# Run this after generating a new version of iptables
TMP_DIR=/tmp/iptables-prep.$$
mkdir --parents $TMP_DIR
SCRATCH="$TMP_DIR"/tmp

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
  echo "... OK, fwsnort update skipped"
else
  echo "... Checking iptables rules for manual insert ..."
  # Initialize sed script
  > "$TMP_DIR/fwsnort_conf_update.sed"
  for CHAIN in INPUT OUTPUT FORWARD; do
    cat /etc/sysconfig/iptables \
    | grep -e "^--append $CHAIN" -e "^-A $CHAIN" -e "#.*INSERT FWSNORT_$CHAIN HERE" \
    | grep --line-number "INSERT FWSNORT_$CHAIN HERE" \
    | cut --fields=1 --delimiter=":" \
    | tr "\n" " " \
      > "$SCRATCH"
    if [[ ! -s "$SCRATCH" ]]; then
      echo "... no manual insert rules specified for $CHAIN, setting as 1 ..."
    fi
    CHAIN_START=`cat $SCRATCH | tr -d "\n \t"`
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
  echo "... OK, fwsnort update skipped"
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

