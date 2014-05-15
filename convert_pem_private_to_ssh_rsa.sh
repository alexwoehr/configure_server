#!/bin/sh

# Taken from https://gist.github.com/crowdmatt/5391537

echo "WARNING: Script $0 is not tested yet."
exit 255

infile=$1
outfile=$2

openssl rsa -in $infile -pubout > $outfile
# From Public Key:
# openssl rsa -inform pem -pkey -in $infile -pubout > $outfile
ssh-keygen -f $outfile -i -m PKCS8

