#!/bin/bash

source /functions.inc.sh

if [[ -n "${JSON_DATA}" ]]; then
  # Parsing JSON_DATA and prefixing variable names with "var_"
  while IFS="=" read -r name value; do
    eval "export var_${name}='${value}'"
  done < <(echo "${JSON_DATA}" | jq -r 'to_entries | map("\(.key)=\(.value | tostring)") | .[]')
fi


# Executing BASH_DATA script
if [[ -n "${BASH_DATA}" ]]; then
  bash -c "${BASH_DATA}"
fi
