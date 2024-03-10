#!/bin/bash

vault_secret_ad_item() {
  local secretPath=$1
  local newKey=$2
  local newValue=$3
  local currentSecret=$(curl -s -H "X-Vault-Token: ${GLOBAL_VAULT_TOKEN}" "${VAULT_ADDR}/v1/kv/data/${secretPath}" | jq '.data.data')
  local updatedSecret=$(echo ${currentSecret} | jq --arg key "${newKey}" --arg value "$newValue" '. + {($key): $value}')
  curl -s -o /dev/null -w "%{http_code}" -X PUT -H "X-Vault-Token: ${GLOBAL_VAULT_TOKEN}" -H "Content-Type: application/json" --data "{\"data\": ${updatedSecret}}" "${VAULT_ADDR}/v1/kv/data/${secretPath}" > /dev/null
}
function add_file_on_git() {
  local GIT_URL=$1
  local GIT_REPO="${GIT_URL##*/}"
  local THE_FILE=$2
  local CONTENTS=$3
  # Cleanup and clone the repository
  rm -rf /tmp/${GIT_REPO} 2>/dev/null || true
  cd /tmp && git clone https://lukas-pastva:${GLOBAL_GIT_TOKEN}@${GIT_URL} >/dev/null 2>&1
  # Save file
  echo -e "${CONTENTS}" > "/tmp/${GIT_REPO}/${THE_FILE}"
  # Commit changes
  cd /tmp/${GIT_REPO}
  git add . >/dev/null 2>&1
  git commit -m "Added by devops/sys-terraform" >/dev/null 2>&1
  git push >/dev/null 2>&1
}
update_ingress_url() {
  local namespace=$1
  local ingress_name=$2
  local new_domain=$3
  local api_server="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"
  local token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  local ingress_path="/apis/networking.k8s.io/v1/namespaces/${namespace}/ingresses/${ingress_name}"
  local ingress_json=$(curl -sSk -H "Authorization: Bearer ${token}" "${api_server}${ingress_path}")
  local updated_json=$(echo "${ingress_json}" | jq --arg new_domain "${new_domain}" '.spec.rules[0].host = $new_domain')
  curl -sSk -X PUT -H "Authorization: Bearer ${token}" -H 'Content-Type: application/json' -d "${updated_json}"  "${api_server}${ingress_path}" > /dev/null
}

function edit_file_on_git() {
  local GIT_URL=$1
  local GIT_REPO="${GIT_URL##*/}"
  local ANCHOR=$2
  local THE_FILE=$3
  local CONTENTS=$4

  # Cleanup and clone the repository
  rm -rf /tmp/${GIT_REPO} 2>/dev/null || true
  cd /tmp && git clone https://lukas-pastva:${GLOBAL_GIT_TOKEN}@${GIT_URL} >/dev/null 2>&1

  # Check if CONTENTS already exists in the file
  if ! grep -Fq "$CONTENTS" "/tmp/${GIT_REPO}/${THE_FILE}"; then
    # CONTENTS not found; proceed with adding it to the file

    # Save file
    preprocessed_VAR=$(printf '%s' "$CONTENTS" | sed 's/\\/&&/g;s/^[[:blank:]]/\\&/;s/$/\\/')
    sed -i -e "/GENERATED $ANCHOR START/a\\
    ${preprocessed_VAR%?}" "/tmp/${GIT_REPO}/${THE_FILE}"

    # Commit changes
    cd /tmp/${GIT_REPO}
    git add . >/dev/null 2>&1
    git commit -m "Added by devops/sys-terraform" >/dev/null 2>&1
    git push >/dev/null 2>&1
  else
    echo "---> Contents already exist in the file. No changes made."
  fi
}
