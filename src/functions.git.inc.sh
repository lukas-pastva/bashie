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

    # Commit changes
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
  if [[ ${gitlab_private_token} == "" ]]; then
      echo "Enter your GitLab Private Token: "
      read gitlab_private_token
      export gitlab_private_token="${gitlab_private_token}"
  fi

  if [[ ${group_id} == "" ]]; then
      echo "Enter your GitLab Group ID: "
      read group_id
      export group_id="${group_id}"
  fi

  _backup_variables() {
      local project_id=$1
      local backup_dir=$2
      echo "Backing up variables for project ID $project_id"
      curl --silent --header "PRIVATE-TOKEN: $gitlab_private_token" \
          "https://gitlab.com/api/v4/projects/$project_id/variables" > "$backup_dir/variables.json"
  }

  # Function to backup project issues and comments
  _backup_issues() {
      local project_id=$1
      local backup_dir=$2
      echo "Backing up issues and comments for project ID $project_id"

      # Fetch issues for the project
      local issues_response=$(curl --silent --header "PRIVATE-TOKEN: $gitlab_private_token" \
          "https://gitlab.com/api/v4/projects/$project_id/issues?with_labels_details=true&include_subscribed=true&per_page=100")

      # Check if there are issues available
      if [[ -z "$issues_response" || "$issues_response" == "[]" ]]; then
          echo "No issues found for project ID $project_id."
          return
      fi

      # Iterate through each issue and fetch its comments
      echo "$issues_response" | jq -c '.[]' | while IFS= read -r issue; do
          local issue_iid=$(echo "$issue" | jq -r '.iid')

          # Fetch comments for the issue
          local issue_comments_response=$(curl --silent --header "PRIVATE-TOKEN: $gitlab_private_token" \
              "https://gitlab.com/api/v4/projects/$project_id/issues/$issue_iid/notes")

          # Check if comments were fetched successfully
          if [[ -n "$issue_comments_response" && "$issue_comments_response" != "[]" ]]; then
              # Save comments to a file
              echo "$issue_comments_response" > "$backup_dir/issue_${issue_iid}_comments.json"
          else
              echo "No comments found for issue IID $issue_iid in project ID $project_id."
          fi
      done

  }

  # Function to backup CI/CD settings for a group
  _backup_cicd_settings() {
      local group_id=$1
      local backup_dir=$2
      echo "Backing up CI/CD settings for group ID ${group_id}"
      curl --silent --header "PRIVATE-TOKEN: $gitlab_private_token" "https://gitlab.com/api/v4/groups/${group_id}/ci/pipeline_schedules" > "$backup_dir/cicd_pipeline_schedules.json"
  }

  # Function to backup group issues
  _backup_group_issues() {
      local group_id=$1
      local backup_dir=$2
      echo "Backing up issues for group ID ${group_id}"
      curl --silent --header "PRIVATE-TOKEN: $gitlab_private_token" \
          "https://gitlab.com/api/v4/groups/${group_id}/issues" > "$backup_dir/group_issues.json"
  }

  # New function to backup CI/CD variables for a group
  _backup_group_variables() {
      local group_id=$1
      local backup_dir=$2
      echo "Backing up CI/CD variables for group ID ${group_id}"
      curl --silent --header "PRIVATE-TOKEN: $gitlab_private_token" \
          "https://gitlab.com/api/v4/groups/${group_id}/variables" > "$backup_dir/group_variables.json"
  }

  # Function to zip and clean up the backup directories
  _zip_and_cleanup() {
      local backup_root_dir=$1  # The root directory where all backups are stored
      local zip_destination_dir=$2  # The destination directory for the zip file
      local group_id=$3         # GitLab Group ID to include in the zip filename

      echo "Compressing backup directories into a single archive..."
      # Creating a ZIP file for the entire backup directory, including the Group ID in the filename
      # The zip file is now created in the specified destination directory
      zip -q -r "${zip_destination_dir}/gitlab_backup_group_${group_id}_${date_and_time}.zip" "$backup_root_dir" -x "*.zip"

      echo "Removing original backup directories..."
      # Find and delete the original directories but keep the zip file
      rm -rf "$backup_root_dir"

  }

  # Recursive function to clone projects and handle subgroups, including variables, issues, CI/CD settings, and CI/CD variables backup
  _clone_recursive() {
      local current_group_id=$1
      local parent_dir=$2

      # Backup CI/CD settings, CI/CD variables, and issues for the current group
      _backup_cicd_settings "$current_group_id" "$parent_dir"
      _backup_group_issues "$current_group_id" "$parent_dir"
      _backup_group_variables "$current_group_id" "$parent_dir" # Call to backup group CI/CD variables

      local page=1
      while : ; do
          local projects_response=$(curl --silent --header "PRIVATE-TOKEN: $gitlab_private_token" \
              "https://gitlab.com/api/v4/groups/$current_group_id/projects?include_subgroups=true&per_page=100&page=$page")
          local project_count=$(echo "$projects_response" | jq '. | length')
          if [[ "$project_count" -eq 0 ]]; then break; fi

          echo "$projects_response" | jq -c '.[]' | while read project; do
              local project_id=$(echo $project | jq -r '.id')
              local project_path=$(echo $project | jq -r '.path_with_namespace')
              local http_url_to_repo=$(echo $project | jq -r '.http_url_to_repo')
              local clone_dir="$parent_dir/${project_path}"

              local modified_clone_url=$(echo "$http_url_to_repo" | sed "s|https://|https://user:$gitlab_private_token@|")

              # Cloning the regular repository
              if [ -d "$clone_dir" ] && [ "$(ls -A $clone_dir)" ]; then
                  echo "Directory $clone_dir already exists and is not empty. Attempting to pull latest changes."
                  (cd "$clone_dir" && git pull)
              else
                  echo "Cloning all branches of $modified_clone_url into $clone_dir"
                  mkdir -p "$clone_dir"
                  git clone --quiet "$modified_clone_url" "$clone_dir" > /dev/null 2>&1
              fi

              # Cloning the mirror repository
              local mirror_dir="${parent_dir}/${project_path}_mirror"
              if [ -d "$mirror_dir" ]; then
                  echo "Mirror directory $mirror_dir already exists. Attempting to update the mirror."
                  (cd "$mirror_dir" && git remote update)
              else
                  echo "Cloning a mirror of $modified_clone_url into $mirror_dir"
                  mkdir -p "$mirror_dir"
                  git clone --quiet --mirror "$modified_clone_url" "$mirror_dir" > /dev/null 2>&1
              fi

              # Backing up variables and issues
              _backup_variables "$project_id" "$clone_dir"
              _backup_issues "$project_id" "$clone_dir"
          done

          ((page++))
      done

      page=1
      while : ; do
          local subgroups_response=$(curl --silent --header "PRIVATE-TOKEN: $gitlab_private_token" \
              "https://gitlab.com/api/v4/groups/$current_group_id/subgroups?per_page=100&page=$page")
          local subgroup_count=$(echo "$subgroups_response" | jq '. | length')
          if [[ "$subgroup_count" -eq 0 ]]; then break; fi

          echo "$subgroups_response" | jq -c '.[]' | while read subgroup; do
              local subgroup_id=$(echo $subgroup | jq -r '.id')
              local subgroup_dir="$parent_dir/$(echo $subgroup | jq -r '.full_path')"

              mkdir -p "$subgroup_dir"
              _backup_group_issues "$subgroup_id" "$subgroup_dir"
              _backup_group_variables "$subgroup_id" "$subgroup_dir" # Backup group CI/CD variables for subgroups

              _clone_recursive "$subgroup_id" "$parent_dir"
          done

          ((page++))
      done
  }

  local date_and_time=$(date +%Y-%m-%d_%H-%M-%S)
  local backup_root_dir="/tmp/backup/files"
  local zip_destination_dir="/tmp/backup/zip"
  mkdir -p "${backup_root_dir}"
  mkdir -p "${zip_destination_dir}"
  _clone_recursive "${group_id}" "${backup_root_dir}"
  _zip_and_cleanup "${backup_root_dir}" ${zip_destination_dir} "${group_id}"
  echo "---------------------------------------------------------------------------------------------------------------"
  echo "Backup completed, zip stored in ${zip_destination_dir}/"
  echo "---------------------------------------------------------------------------------------------------------------"

  if [ -n "$rclone_bucket" ]; then
    echo "RClone is enabled, uploading backup"
    rclone --config /tmp/rclone.conf copy "${zip_destination_dir}/gitlab_backup_group_${group_id}_${date_and_time}.zip" "s3:${rclone_bucket}/gitlab/gitlab-backup_${group_id}_${date_and_time}"
  fi
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


