#!/bin/bash

vault_secret_ad_item() {
  local secretPath=$1
  local newKey=$2
  local newValue=$3
  local currentSecret=$(curl -s -H "X-Vault-Token: ${GLOBAL_VAULT_TOKEN}" "${VAULT_ADDR}/v1/kv/data/${secretPath}" | jq '.data.data')
  local updatedSecret=$(echo ${currentSecret} | jq --arg key "${newKey}" --arg value "$newValue" '. + {($key): $value}')
  curl -s -o /dev/null -w "%{http_code}" -X PUT -H "X-Vault-Token: ${GLOBAL_VAULT_TOKEN}" -H "Content-Type: application/json" --data "{\"data\": ${updatedSecret}}" "${VAULT_ADDR}/v1/kv/data/${secretPath}"
}

function vault_secret_add_line() {
  local secretPath=$1
  local targetKey=$2
  local newLineValue=$3

  # Fetch the current secret from Vault
  local currentSecret=$(curl -s -H "X-Vault-Token: ${GLOBAL_VAULT_TOKEN}" \
    "${VAULT_ADDR}/v1/kv/data/${secretPath}" | jq -r ".data.data | .[\"$targetKey\"]")

  # Append new line to the existing value
  local updatedValue="${currentSecret}
${newLineValue}"

  # Prepare the updated secret payload
  local updatedSecret=$(jq -n --arg key "$targetKey" --arg value "$updatedValue" \
    '{data: {($key): $value}}')

  # Update the secret in Vault
  local statusCode=$(curl -s -o /dev/null -w "%{http_code}" -X PUT -H "X-Vault-Token: ${GLOBAL_VAULT_TOKEN}" \
    -H "Content-Type: application/json" --data "$updatedSecret" \
    "${VAULT_ADDR}/v1/kv/data/${secretPath}")

  # Optional: Check if the operation was successful
  if [[ "$statusCode" == "200" ]]; then
    echo_with_time "Successfully updated the secret."
  else
    echo_with_time "Failed to update the secret. Status code: $statusCode"
  fi
}

function vault_secrets_delete_with_test_prefix() {
    # Find the Vault pod and namespace
    local VAULT_POD_INFO=$(kubectl get pods --all-namespaces -l app.kubernetes.io/name=vault -o jsonpath="{.items[0].metadata.name} {.items[0].metadata.namespace}")
    local VAULT_POD=$(echo "$VAULT_POD_INFO" | cut -d' ' -f1)
    local VAULT_NAMESPACE=$(echo "$VAULT_POD_INFO" | cut -d' ' -f2)

    if [ -z "$VAULT_POD" ] || [ -z "$VAULT_NAMESPACE" ]; then
        echo "Vault pod could not be found."
        return
    fi

    # Setup port forwarding
    kubectl port-forward -n "$VAULT_NAMESPACE" "$VAULT_POD" 8200:8200 &
    local PF_PID=$!
    sleep 2 # Wait for port forwarding to establish

    # Prompt for Vault token
    echo -n "Enter Vault Token: "
    read -rs VAULT_TOKEN
    echo "" # Move to a new line

    # Set Vault address
    local VAULT_ADDR="http://localhost:8200"

    # List groups with the 'test-' prefix
    local GROUPS_LIST=$(curl -s -X LIST --header "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/kv/metadata/remp" | jq -r '.data.keys[]' | grep ^test-)

    if [ -z "$GROUPS_LIST" ]; then
        echo "No groups matching 'test-' prefix found."
        kill $PF_PID
        return
    fi

    # Save and change IFS to only split on newlines
    OLD_IFS=$IFS
    IFS=$'\n'

    while read -r group; do
        group="${group%/}/" # Ensure group ends with a slash

        local SECRETS_LIST=$(curl -s -X LIST --header "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/kv/metadata/remp/$group" | jq -r '.data.keys[]')

        if [ -z "$SECRETS_LIST" ] || [ "$SECRETS_LIST" == "null" ]; then
            echo "No secrets found in group $group"
            continue
        fi

        echo "The following secrets will be deleted in group $group:"
        echo "$SECRETS_LIST"

        echo -n "Secrets from group $group above, will be now deleted, you have 10 seconds to cancel... "
        sleep 10

        echo "$SECRETS_LIST" | while read -r secret; do
            echo "Deleting secret: $group$secret"
            curl --request DELETE --header "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/kv/metadata/remp/$group$secret"
        done
    done < <(echo "$GROUPS_LIST")

    IFS=$OLD_IFS
    kill $PF_PID
}
