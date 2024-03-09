#!/bin/bash

echo ""
echo "--------------------------------------------------------"
echo "Parsing JSON_DATA to environment variables..."
# Only proceed if JSON_DATA is not empty
if [[ -n "${JSON_DATA}" ]]; then
  # Parsing JSON_DATA and prefixing variable names with "var_"
  while IFS="=" read -r name value; do
    # Using eval to handle complex scenarios safely
    eval "export var_${name}='${value}'"
  done < <(echo "${JSON_DATA}" | jq -r 'to_entries | map("\(.key)=\(.value | tostring)") | .[]')
  echo "Environment variables are set."
else
  echo "JSON_DATA is empty. Skipping setting environment variables."
fi
echo "--------------------------------------------------------"


echo ""
echo "--------------------------------------------------------"
echo "Executing BASH_DATA script..."
# Only proceed if BASH_DATA is not empty
if [[ -n "${BASH_DATA}" ]]; then
  # Directly execute BASH_DATA content
  bash -c "${BASH_DATA}"
  echo "BASH_DATA script executed."
else
  echo "BASH_DATA is empty. Skipping script execution."
fi
echo "--------------------------------------------------------"