#!/bin/bash

echo ""
echo "--------------------------------------------------------"
echo "Parsing JSON_DATA to environment variables..."
for row in $(echo "${JSON_DATA}" | jq -r "to_entries|map(\"\(.key)=var_\(.value|tostring)\")|.[]"); do
  export $row
done
echo "Environment variables are set."


echo ""
echo "--------------------------------------------------------"
echo "Executing BASH_DATA script..."
echo "$BASH_DATA" > /tmp/bash.sh
bash /tmp/bash.sh