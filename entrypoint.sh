#!/bin/bash
echo "Parsing JSON_DATA to environment variables..."
for row in $(echo "${JSON_DATA}" | jq -r "to_entries|map(\"\(.key)=VAR_\(.value|tostring)\")|.[]"); do
  export $row
done
echo "Environment variables are set."

# Use a temporary file to store BASH_DATA
BASH_DATA_FILE=$(mktemp)
echo "Storing BASH_DATA script in temporary file..."
echo "$BASH_DATA" > "$BASH_DATA_FILE"

echo "Executing BASH_DATA script..."
bash "$BASH_DATA_FILE"

# Clean up
rm "$BASH_DATA_FILE"