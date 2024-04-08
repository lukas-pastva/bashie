#!/bin/bash

source /functions.inc.sh

echo_with_time "Parsing JSON_DATA to environment variables..."
# Only proceed if JSON_DATA is not empty
if [[ -n "${JSON_DATA}" ]]; then
  # Parsing JSON_DATA and prefixing variable names with "var_"
  while IFS="=" read -r name value; do
    # Using eval to handle complex scenarios safely
    eval "export var_${name}='${value}'"
  done < <(echo "${JSON_DATA}" | jq -r 'to_entries | map("\(.key)=\(.value | tostring)") | .[]')
  echo_with_time "Environment variables are set."
else
  echo_with_time "JSON_DATA is empty. Skipping setting environment variables."
fi


echo_with_time "Executing BASH_DATA script..."
# Only proceed if BASH_DATA is not empty
if [[ -n "${BASH_DATA}" ]]; then
  # Directly execute BASH_DATA content
  bash -c "${BASH_DATA}"
  echo_with_time "BASH_DATA script executed."
else
  echo_with_time "BASH_DATA is empty. Skipping script execution."
fi
