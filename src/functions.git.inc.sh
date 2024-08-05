#!/bin/bash


function git_add_file() {
  local GIT_URL=$1
  local GIT_REPO="${GIT_URL##*/}"
  local THE_FILE=$2
  local CONTENTS=$3

  rm -rf /tmp/${GIT_REPO} || true
  cd /tmp
  git clone --quiet https://lukas-pastva:${GLOBAL_GIT_TOKEN}@${GIT_URL}.git > /dev/null 2>&1
  # Save file
  echo -e "${CONTENTS}" > "/tmp/${GIT_REPO}/${THE_FILE}"
  # Commit changes
  cd /tmp/${GIT_REPO}
  git add . > /dev/null 2>&1
  git commit -m "Added by automation." > /dev/null 2>&1
  git push > /dev/null 2>&1
}

function git_edit_file() {
  local GIT_URL=$1
  local GIT_REPO="${GIT_URL##*/}"
  local ANCHOR=$2
  local THE_FILE=$3
  local CONTENTS=$4
  local UNIQUE_IDENTIFIER=$5

  cd /tmp
  git clone --quiet https://lukas-pastva:${GLOBAL_GIT_TOKEN}@${GIT_URL}.git > /dev/null 2>&1
  cd /tmp/${GIT_REPO}

  # Check if CONTENTS already exists in the file
  if ! grep -Fq "$UNIQUE_IDENTIFIER" "${THE_FILE}"; then

    # Save file
    preprocessed_VAR=$(printf '%s' "$CONTENTS" | sed 's/\\/&&/g;s/^[[:blank:]]/\\&/;s/$/\\/')
    sed -i -e "/GENERATED $ANCHOR START/a\\
    ${preprocessed_VAR%?}" "/tmp/${GIT_REPO}/${THE_FILE}"

    git add . > /dev/null 2>&1
    git commit -m "Added by automation." > /dev/null 2>&1
    git push > /dev/null 2>&1
  else
    echo_with_time "Contents already exist in the file. No changes made."
  fi
  rm -rf /tmp/${GIT_REPO} || true
}


# Function to clone GitLab group repositories, including subgroups, maintaining hierarchy
function gitlab_backup() {
  _backup_data() {
      local entity=$1
      local id=$2
      local path=$3
      local parent_dir=$4
      local endpoint_suffix=$5
      local backup_dir="${parent_dir}/_${entity}/${path}"
      local api_endpoint="${gitlab_url}/api/v4${endpoint_suffix}"
      
      local backup_response=$(curl -s -H "PRIVATE-TOKEN: $gitlab_private_token" "$api_endpoint")
      if [ ${#backup_response} -gt 3 ]; then
          mkdir -p "$backup_dir"
          echo -e "${backup_response}" > "${backup_dir}/${entity}.json"
      fi

      if [ "$entity" == "issues" ]; then
          echo "$backup_response" | jq -c '.[]' | while IFS= read -r issue; do
              local issue_iid=$(echo "$issue" | jq -r '.iid')
              local project_id=$(echo "$issue" | jq -r '.project_id')
              local issue_comments_response=$(curl -s -H "PRIVATE-TOKEN: $gitlab_private_token" "${gitlab_url}/api/v4/projects/${project_id}/issues/${issue_iid}/notes")
              if [[ -n "$issue_comments_response" && "$issue_comments_response" != "[]" ]]; then
                  echo "$issue_comments_response" > "${backup_dir}/issue_${issue_iid}_comments.json"
              fi
          done
      fi
  }

  _clone_branches() {
    local repo_url=$1
    local clone_dir=$2

    local branches=$(git ls-remote --heads $repo_url | awk '{print $2}' | sed 's#refs/heads/##')
    for branch in $branches; do
      local sanitized_branch=$(echo $branch | sed 's/[\/:]/_/g')
      local branch_dir="${clone_dir}/${sanitized_branch}"
      mkdir -p "$branch_dir"
      git clone --branch $branch --single-branch $repo_url $branch_dir > /dev/null 2>&1
    done
  }

  _clone_recursive() {
    local backup_root_dir=$1
    local current_group_id=$2
    local parent_dir=$3

    local page=1
    while : ; do
      local projects_response=$(curl -s -H "PRIVATE-TOKEN: $gitlab_private_token" "${gitlab_url}/api/v4/groups/$current_group_id/projects?include_subgroups=false&with_shared=false&per_page=100&page=$page")
      local project_count=$(echo "$projects_response" | jq '. | length')
      if [[ "$project_count" -eq 0 ]]; then break; fi
      echo "$projects_response" | jq -c '.[]' | while IFS= read -r project_to_fix; do

        local project=$(echo "$project_to_fix" | sed -E 's/"description_html":"([^"]*)"/"description_html":"\1"/g' | sed 's/\(description_html[^"]*:[^"]*\)"\([^"]*\)"/\1\\"/g')
        local project_id=$(echo $project | jq -r '.id')
        local project_path="$(echo $project | jq -r '.path_with_namespace')"
        local http_url_to_repo=$(echo $project | jq -r '.http_url_to_repo')
        local clone_dir="$backup_root_dir/_repositories/${project_path}"

        echo "Project: ${project_path}"
        
        mkdir -p "$clone_dir"
        local modified_clone_url=$(echo "$http_url_to_repo" | sed "s|https://|https://user:$gitlab_private_token@|")
        _clone_branches "$modified_clone_url" "$clone_dir"


        local mirror_dir="${backup_root_dir}/_mirror/${project_path}"
        mkdir -p "$mirror_dir"
        git clone --quiet --mirror "$modified_clone_url" "$mirror_dir" > /dev/null 2>&1

        _backup_data "variables" $project_id $project_path $parent_dir "/projects/${project_id}/variables"
        _backup_data "pipeline_schedules" $project_id $project_path $backup_root_dir "/projects/${project_id}/pipeline_schedules"
        _backup_data "wikis" $project_id $project_path $parent_dir "/projects/${project_id}/wikis"
        _backup_data "merge_requests" $project_id $project_path $parent_dir "/projects/${project_id}/merge_requests?state=all"
        _backup_data "snippets" $project_id $project_path $parent_dir "/projects/${project_id}/snippets"
        _backup_data "issues" $project_id $project_path $backup_root_dir "/projects/${project_id}/issues?with_labels_details=true&include_subscribed=true&per_page=100"
      done

      ((page++))
    done

    page=1
    while : ; do
        local subgroups_response=$(curl -s -H "PRIVATE-TOKEN: $gitlab_private_token" "${gitlab_url}/api/v4/groups/$current_group_id/subgroups?per_page=100&page=$page")
        local subgroup_count=$(echo "$subgroups_response" | jq '. | length')
        if [[ "$subgroup_count" -eq 0 ]]; then break; fi

        echo "$subgroups_response" | jq -c '.[]' | while read subgroup; do
            local subgroup_id=$(echo $subgroup | jq -r '.id')
            local group_path="$(echo $subgroup | jq -r '.full_path')"

            echo "Group: ${group_path}"

            _backup_data "variables_group" $group_id $group_path $backup_root_dir "/groups/${group_id}/variables"

            _clone_recursive "${backup_root_dir}" "$subgroup_id" "$parent_dir"
        done

        ((page++))
    done
  }

  # init
  local date_and_time=$(date +%Y-%m-%d_%H-%M-%S)
  if [[ ${gitlab_private_token} == "" ]]; then
    echo "Enter your GitLab Private Token: " && read gitlab_private_token && export gitlab_private_token="${gitlab_private_token}"
  fi
  if [[ ${group_id} == "" ]]; then
    echo "Enter your GitLab Group ID: " && read group_id && export group_id="${group_id}"
  fi
  if [[ ${gitlab_url} == "" ]]; then
    gitlab_url="https://gitlab.com"
  fi
  if [[ ${backup_dir} == "" ]]; then
    backup_root_dir="/tmp/backup/files" && zip_destination_dir="/tmp/backup/zip"
  else
    case "${backup_dir}" in
      "/"|"/mnt"|"/c"|"/d"|"/e"|"/f"|"/home"|"/root"|"/etc"|"/var"|"/usr"|"/bin"|"/sbin"|"/lib"|"/lib64"|"/opt")
        echo "Error: backup_dir cannot be set to a critical system directory."
        return 1
        ;;
      *)
        backup_root_dir="${backup_dir}/files"
        zip_destination_dir="${backup_dir}/zip"
        ;;
    esac
  fi

  # chicken egg
  local group_path=$(curl -s -H "PRIVATE-TOKEN: $gitlab_private_token" "${gitlab_url}/api/v4/groups/${group_id}" | jq -r '.name')
  _backup_data "variables_group" $group_id $group_path $backup_root_dir "/groups/${group_id}/variables"
  _clone_recursive "${backup_root_dir}" "${group_id}" "${backup_root_dir}"

  echo "Zipping ..."
  mkdir -p ${zip_destination_dir} && zip -q -r "${zip_destination_dir}/gitlab_backup_group_${group_id}_${date_and_time}.zip" "$backup_root_dir" -x "*.zip"

  echo "Cleanup ..."
  if [[ "$backup_root_dir" == *"/files"* ]]; then
    find "$backup_root_dir" -mindepth 1 -delete
  else
    echo "Cannot cleanup, directory does not contain '/files'"
  fi

  if [ -n "$rclone_bucket" ]; then
    echo "RClone is enabled, uploading backup"
    rclone --config /tmp/rclone.conf copy "${zip_destination_dir}/gitlab_backup_group_${group_id}_${date_and_time}.zip" "s3:${rclone_bucket}/gitlab"
  fi

  echo "Done."

}

function gitlab_update_file() {
    project_id="$1"
    file_path="$2"
    branch_name="$3"
    commit_message="$4"
    file_contents="$5"

    # Encode the file path for URL
    encoded_file_path=$(printf '%s' "$file_path" | jq -sRr @uri)

    # Construct the API URL dynamically, ensuring there's no newline character at the end
    api_url="https://gitlab.com/api/v4/projects/${project_id}/repository/files/${encoded_file_path}"

    # Ensure the file contents are properly escaped as a JSON string
    json_safe_contents=$(echo "$file_contents" | jq -sR .)

    curl --silent --request PUT "$api_url" \
        --header "PRIVATE-TOKEN: $GLOBAL_GIT_TOKEN" \
        --header "Content-Type: application/json" \
        --data "{
            \"branch\": \"${branch_name}\",
            \"author_email\": \"$GLOBAL_GIT_EMAIL\",
            \"author_name\": \"$GLOBAL_GIT_USER\",
            \"content\": $json_safe_contents,
            \"commit_message\": \"${commit_message}\"
        }" # > /dev/null 2>&1
}