#!/usr/bin/env bash

echo "Here are current running processes from mysql. (You will need to enter root password.)"
echo "SHOW PROCESSLIST;" \
| mysql -u root -p

echo "Is it okay to restart mysql? [y/n]"
read prompt

if [[ $prompt == "y" ]]; then
  echo "Stopping mysql..."
  service mysqld stop
else
  echo "Okay, not stopping mysql."
fi

