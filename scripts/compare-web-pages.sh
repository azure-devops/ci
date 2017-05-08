#!/bin/bash

function print_usage() {
  cat <<EOF
Command
  $0
Arguments
  --first_url|-f       [Required]: First URL
  --second_url|-s      [Required]: Second URL
  --replace_domain|-d            : Replaces the {domain-name} token in the content of first_url with this argument
EOF
}

function throw_if_empty() {
  local name="$1"
  local value="$2"
  if [ -z "$value" ]; then
    >&2 echo "Parameter '$name' cannot be empty."
    print_usage
    exit -1
  fi
}

while [[ $# > 0 ]]
do
  key="$1"
  shift
  case $key in
    --first_url|-f)
      first_url="$1"
      shift
      ;;
    --second_url|-s)
      second_url="$1"
      shift
      ;;
    --replace_domain|-d)
      replace_domain="$1"
      shift
      ;;
    --help|-help|-h)
      print_usage
      exit 13
      ;;
    *)
      >&2 echo "ERROR: Unknown argument '$key' to script '$0'"
      exit -1
  esac
done

throw_if_empty --first_url $first_url
throw_if_empty --second_url $second_url

if [ -z "$replace_domain" ]; then
  diff -w <(curl -s -L $first_url ) <(curl -s -L $second_url )
else
  diff -w  <(curl -s -L $first_url | sed -e "s|{domain-name}|$replace_domain|" ) <(curl -s -L $second_url )
fi