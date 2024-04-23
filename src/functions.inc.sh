#!/bin/bash

source /functions.git.inc.sh || true
source /functions.vault.inc.sh || true

function k8s_ingress_update_url() {
  local namespace=$1
  local ingress_name=$2
  local new_domain=$3
  local api_server="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"
  local token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  local ingress_path="/apis/networking.k8s.io/v1/namespaces/${namespace}/ingresses/${ingress_name}"
  local ingress_json=$(curl -sSk -H "Authorization: Bearer ${token}" "${api_server}${ingress_path}")
  local updated_json=$(echo "${ingress_json}" | jq --arg new_domain "${new_domain}" '.spec.rules[0].host = $new_domain')
  curl -sSk -X PUT -H "Authorization: Bearer ${token}" -H 'Content-Type: application/json' -d "${updated_json}" "${api_server}${ingress_path}" > /dev/null 2>&1
}

function k(){
  kubectl "$@"
}

function kdeleteall() {
    local namespace="$1"

    if [ -z "$namespace" ]; then
        echo "Usage: kdeleteall <namespace>"
        return 1
    fi

    echo "Are you sure you want to delete all resources in namespace '$namespace'? [y/N]"
    read confirmation
    if [[ "$confirmation" =~ ^[Yy]$ ]]; then
        # Get all types of resources (including CRDs that are namespace-scoped)
        kubectl api-resources --verbs=delete --namespaced=true -o name | while read -r resource; do
            # Attempt to delete each resource type individually
            echo "Deleting all $resource in $namespace..."
            kubectl delete "$resource" --all -n "$namespace"
        done

        echo "All possible deletable resources in namespace '$namespace' have been processed."
    else
        echo "Deletion cancelled."
    fi
}

function e(){
  cd ~/Desktop/_envs
}

function echo_with_time() {
  # Get current time in UTC in Z format
  local current_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Add an empty line before the text
  echo

  # Check if the last character of the input is a newline
  if [[ "$1" == $'\n' || "$1" == *$'\n' ]]; then
    # If there's already a newline, just print the text with the timestamp and add one empty line after
    echo -e "${current_time} $1"
  else
    # If there's no newline at the end, add the text with the timestamp and two empty lines after
    echo -e "${current_time} $1\n"
  fi
}
#
#function git_set_remote() {
#  if [ "$#" -ne 2 ]; then
#    echo "Usage: set_git_remote <repo_url> <token>"
#    echo "  <repo_url>: The URL of the repository where you want to change the remote (e.g., https://github.com/username/new-repository.git)"
#    echo "  <token>: Your personal access token for authentication"
#    return 1
#  fi
#
#  local repo_url=$1
#  local token=$2
#
#  # Check if the URL has 'https://' at the start and strip it out because we'll add it along with the token
#  if [[ $repo_url =~ ^https:// ]]; then
#    repo_url="${repo_url#https://}"
#  fi
#
#  # Construct the new URL with the token
#  local new_url="https://${token}@${repo_url}"
#
#  # Set the new URL to the Git remote named 'origin'
#  git remote set-url origin "$new_url"
#  echo "Remote URL set to ${new_url}"
#}

# Enable debugging if DEBUG environment variable is set
if [ "$DEBUG" = "true" ]; then
  set -x
fi
