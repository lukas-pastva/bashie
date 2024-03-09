#!/bin/bash

# Function to export environment variables from JSON_DATA
export_env_variables() {
  echo ""
  echo "--------------------------------------------------------"
  echo "Parsing JSON_DATA to environment variables..."
  if [[ -n "${JSON_DATA}" ]]; then
    while IFS="=" read -r key value; do
      # Export environment variables with proper quoting
      export "$key"="$value"
    done < <(echo "${JSON_DATA}" | jq -r 'to_entries|map("var_\(.key)=\(.value|tostring)")|.[]' 2> /dev/null)

    if [ $? -ne 0 ]; then
        echo "Error parsing JSON_DATA with jq."
        exit 1
    fi

    echo "Environment variables are set."
  else
    echo "JSON_DATA is empty. Skipping environment variables setup."
  fi
  echo "--------------------------------------------------------"
}

# Function to execute BASH_DATA script
execute_bash_data() {
  echo ""
  echo "--------------------------------------------------------"
  echo "Executing BASH_DATA script..."
  if [[ -n "${BASH_DATA}" ]]; then
    bash -c "${BASH_DATA}"
  else
    echo "BASH_DATA is empty. Skipping script execution."
  fi
  echo "--------------------------------------------------------"
}

# Main script execution
export_env_variables
execute_bash_data