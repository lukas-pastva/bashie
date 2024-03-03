#!/bin/bash
echo "Parsing JSON_DATA to environment variables..."
for row in $(echo "${JSON_DATA}" | jq -r "to_entries|map(\"\(.key)=VAR_\(.value|tostring)\")|.[]"); do
  export $row
done
echo "Environment variables are set."

# Use a temporary file to store BASH_DATA
echo "Storing BASH_DATA script in temporary file..."
echo "$BASH_DATA" > /tmp/bash.sh

echo "Cating BASH_DATA script..."
cat /tmp/bash.sh

echo "Executing BASH_DATA script..."
bash /tmp/bash.sh
