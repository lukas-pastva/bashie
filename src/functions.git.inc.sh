#!/bin/bash

# -----------------------------------------------------------------
#  debug logger – prints only when you run with  DEBUG=1 …
# -----------------------------------------------------------------
_dbg() { [[ -n "${DEBUG:-}" ]] && echo "[${FUNCNAME[1]}] $*" >&2; }

function gitlab_user_statistics() {

  # Declare global variables within the function
  declare -A user_commit_count  # Declare globally to ensure it's accessible throughout the script
  total_commits=0               # Global variable to hold the total commits
  project_users=""              # Global variable to hold project users
  project_commit_count=0        # Global variable to hold commits per project

  # Prompt user for GitLab URL and Access Token
  read -p "Enter GitLab URL (e.g., https://gitlab.yourdomain.com): " GITLAB_URL
  read -s -p "Enter your GitLab Access Token: " PRIVATE_TOKEN
  echo    # To add a newline after the token prompt

  # Set the output file name
  OUTPUT_FILE="gitlab_stats.txt"

  # Date range for last month's activity (Adjust as necessary)
  SINCE_DATE=$(date -d "1 month ago" +"%Y-%m-%dT00:00:00Z")
  UNTIL_DATE=$(date +"%Y-%m-%dT23:59:59Z")

  # Function to get all items across all pages
  get_all_items() {
    local url="$1"
    local items=()
    local page=1
    local per_page=100

    while :; do
      response=$(curl --silent --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" "$url&page=$page&per_page=$per_page")
      item_count=$(echo "$response" | jq 'length')

      if [[ $item_count -eq 0 ]]; then
        break
      fi

      items+=($(echo "$response" | jq -r '.[].id'))
      ((page++))
    done

    echo "${items[@]}"
  }

  # Function to get all groups
  get_groups() {
    local url="$GITLAB_URL/api/v4/groups?"
    get_all_items "$url"
  }

  # Function to get all projects in a group
  get_projects_in_group() {
    local group_id=$1
    local url="$GITLAB_URL/api/v4/groups/$group_id/projects?"
    get_all_items "$url"
  }

  # Function to get project details (path and name)
  get_project_details() {
    local project_id=$1
    curl --silent --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" "$GITLAB_URL/api/v4/projects/$project_id"
  }

  # Function to get all commits for a project in the last month
  get_commits_for_project() {
    local project_id=$1
    local commits=()
    local page=1
    local per_page=100

    while :; do
      response=$(curl --silent --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" "$GITLAB_URL/api/v4/projects/$project_id/repository/commits?since=$SINCE_DATE&until=$UNTIL_DATE&page=$page&per_page=$per_page")
      commit_count=$(echo "$response" | jq 'length')

      if [[ $commit_count -eq 0 ]]; then
        break
      fi

      commits+=($(echo "$response" | jq -r '.[] | @base64'))
      ((page++))
    done

    echo "${commits[@]}"
  }

  # Function to collect user commits and accumulate totals for both users and commits
  get_commit_count_per_user() {
    local project_id=$1
    local commits_encoded=($(get_commits_for_project $project_id))
    local project_user_list=()

    # Initialize project commit count
    project_commit_count=0

    # Extract user emails and count commits per user
    for commit_enc in "${commits_encoded[@]}"; do
      commit=$(echo "$commit_enc" | base64 --decode)
      email=$(echo "$commit" | jq -r '.author_email')
      email=$(echo "$email" | xargs)  # Trim whitespace

      # Validate the email and count commits
      if [[ -n "$email" && "$email" != "null" && "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        project_user_list+=("$email")
        user_commit_count["$email"]=$(( ${user_commit_count["$email"]} + 1 ))
      fi
      total_commits=$((total_commits + 1))                # Increment total commit count globally
      project_commit_count=$((project_commit_count + 1))  # Increment project commit count
    done

    # Create a comma-separated list of unique emails
    local unique_emails=$(echo "${project_user_list[@]}" | tr ' ' '\n' | sort -u | tr '\n' ', ' | sed 's/, $//')
    project_users="$unique_emails"  # Set the global variable
  }

  # Start writing to the output file
  echo "GitLab User Statistics" | tee "$OUTPUT_FILE"
  echo "Date range: $SINCE_DATE to $UNTIL_DATE" | tee -a "$OUTPUT_FILE"
  echo "=============================================" | tee -a "$OUTPUT_FILE"

  # Loop through all groups and projects, and count commits for each user
  echo "Fetching groups and repositories..." | tee -a "$OUTPUT_FILE"

  group_ids=($(get_groups))

  for group in "${group_ids[@]}"; do
    project_ids=($(get_projects_in_group $group))
    for project in "${project_ids[@]}"; do
      # Get project details (name and path)
      project_details=$(get_project_details $project)
      project_name=$(echo "$project_details" | jq -r '.name')
      project_path=$(echo "$project_details" | jq -r '.path_with_namespace')

      # Call the function without command substitution
      get_commit_count_per_user $project

      # If project_users is empty, set commit_count to 0; otherwise, count the users
      if [[ -z "$project_users" ]]; then
        commit_count=0
      else
        commit_count=$(echo "$project_users" | tr ',' '\n' | grep -v '^$' | wc -l)  # Ensure no empty lines are counted
      fi

      # Output project details, users, total commits, and other information
      echo "Group ID: $group, Project ID: $project, Project Path: $project_path, Project Name: $project_name" | tee -a "$OUTPUT_FILE"
      echo "Users: $commit_count, Commits in Project: $project_commit_count" | tee -a "$OUTPUT_FILE"

      # Output user list (if any) on a new line
      if [[ -n "$project_users" ]]; then
        echo "Users List:" | tee -a "$OUTPUT_FILE"
        echo "$project_users" | tr ',' '\n' | grep -v '^$' | sed 's/^/ - /' | tee -a "$OUTPUT_FILE"  # Exclude empty lines
      fi
      echo "" | tee -a "$OUTPUT_FILE"  # Add new line after each project's data
    done
  done

  # Print the final summary of users and commit counts
  echo "" | tee -a "$OUTPUT_FILE"
  echo "Final Summary of Users and Commit Counts:" | tee -a "$OUTPUT_FILE"
  echo "=========================================" | tee -a "$OUTPUT_FILE"

  # Print user emails and their total commit counts
  for email in "${!user_commit_count[@]}"; do
    echo "$email: ${user_commit_count[$email]} commits" | tee -a "$OUTPUT_FILE"
  done

  # Print total number of unique users and total commits
  echo "" | tee -a "$OUTPUT_FILE"
  echo "Total number of unique users: ${#user_commit_count[@]}" | tee -a "$OUTPUT_FILE"
  echo "Total number of commits: $total_commits" | tee -a "$OUTPUT_FILE"  # Print total commit count

  echo "Statistics saved to $OUTPUT_FILE"
}

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
  git clone --quiet https://lukas-pastva:${GLOBAL_GIT_TOKEN}@${GIT_URL}.git
  cd /tmp/${GIT_REPO}

  # Check if CONTENTS already exists in the file
  if ! grep -Fq "$UNIQUE_IDENTIFIER" "${THE_FILE}"; then

    # Save file
    preprocessed_VAR=$(printf '%s' "$CONTENTS" | sed 's/\\/&&/g;s/^[[:blank:]]/\\&/;s/$/\\/')
    sed -i -e "/$ANCHOR/a\\
    ${preprocessed_VAR%?}" "/tmp/${GIT_REPO}/${THE_FILE}"

    # Commit changes
    git add .
    git commit -m "Added by automation."
    git push
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

  ############################################################
  #  SAFER git-lab clone-recursive – paste inside gitlab_backup
  ############################################################
  _clone_recursive() {
    local backup_root_dir=$1
    local current_group_id=$2
    local parent_dir=$3

    ########## 1) projects in this group #################################
    local page=1
    while : ; do
      local url="${gitlab_url}/api/v4/groups/${current_group_id}/projects?include_subgroups=false&with_shared=false&per_page=100&page=${page}"
      _dbg "GET  $url"
      local rsp; rsp=$(curl -s -w "%{http_code}" -H "PRIVATE-TOKEN: $gitlab_private_token" "$url")
      local http=${rsp: -3} body=${rsp::-3}
      _dbg "HTTP $http  body preview: $(echo "$body" | head -c120 | tr '\n' ' ')…"

      [[ "$http" != "200" ]] && { echo "[WARN] $url → $http, skipping this page"; break; }
      [[ "$(echo "$body" | jq -r 'type')" != "array" ]] && { echo "[WARN] $url did not return an array – skipping"; break; }
      [[ "$(echo "$body" | jq 'length')" -eq 0 ]] && break   # no more items

      echo "$body" | jq -c '.[]' | while read -r raw; do
        # some HTML descriptions break JSON – light clean-up
        local proj
        proj=$(echo "$raw" |
               sed -E 's/"description_html":"([^"]*)"/"description_html":"\1"/g' |
               sed 's/\(description_html[^"]*:[^"]*\)"\([^"]*\)"/\1\\"/g')

        # verify we still have a proper object with numeric id
        if [[ "$(echo "$proj" | jq -r 'type')" != "object" ]] || \
           ! echo "$proj" | jq -e '.id | numbers' >/dev/null; then
            _dbg "⚠️  malformed entry – skipped: $(echo "$proj" | jq -c '.')"
            continue
        fi

        local project_id project_path repo_url
        project_id=$(echo "$proj"  | jq -r '.id')
        project_path=$(echo "$proj" | jq -r '.path_with_namespace')
        repo_url=$(echo "$proj"    | jq -r '.http_url_to_repo')

        echo "Project: $project_path"

        if [[ -z "$repo_url" || "$repo_url" == "null" ]]; then
            echo "[WARN]  $project_path has no repository URL – skipping code clone"
        else
            local clone_dir="$backup_root_dir/_repositories/$project_path"
            mkdir -p "$clone_dir"
            local remote="${repo_url/https:\/\//https:\/\/user:${gitlab_private_token}@}"
            _clone_branches "$remote" "$clone_dir"

            local mirror_dir="$backup_root_dir/_mirror/$project_path"
            mkdir -p "$mirror_dir"
            git clone --quiet --mirror "$remote" "$mirror_dir" >/dev/null 2>&1
        fi

        # ---------- metadata -------------------------------------------
        _backup_data variables           "$project_id" "$project_path" "$parent_dir"      "/projects/${project_id}/variables"
        _backup_data pipeline_schedules  "$project_id" "$project_path" "$backup_root_dir" "/projects/${project_id}/pipeline_schedules"
        _backup_data wikis               "$project_id" "$project_path" "$parent_dir"      "/projects/${project_id}/wikis"
        _backup_data merge_requests      "$project_id" "$project_path" "$parent_dir"      "/projects/${project_id}/merge_requests?state=all"
        _backup_data snippets            "$project_id" "$project_path" "$parent_dir"      "/projects/${project_id}/snippets"
        _backup_data issues              "$project_id" "$project_path" "$backup_root_dir" "/projects/${project_id}/issues?with_labels_details=true&include_subscribed=true&per_page=100"
      done
      ((page++))
    done

    ########## 2) recurse into sub-groups ################################
    page=1
    while : ; do
      local url="${gitlab_url}/api/v4/groups/${current_group_id}/subgroups?per_page=100&page=${page}"
      _dbg "GET  $url"
      local rsp; rsp=$(curl -s -w "%{http_code}" -H "PRIVATE-TOKEN: $gitlab_private_token" "$url")
      local http=${rsp: -3} body=${rsp::-3}
      [[ "$http" != "200" ]] && { _dbg "HTTP $http – stop subgroup paging"; break; }
      [[ "$(echo "$body" | jq -r 'type')" != "array" ]] && break
      [[ "$(echo "$body" | jq 'length')" -eq 0 ]] && break

      echo "$body" | jq -c '.[]' | while read -r sg; do
        local subgroup_id group_path
        subgroup_id=$(echo "$sg" | jq -r '.id')
        group_path=$(echo "$sg"  | jq -r '.full_path')
        echo "Group: $group_path"

        _backup_data variables_group "$subgroup_id" "$group_path" "$backup_root_dir" "/groups/${subgroup_id}/variables"
        _clone_recursive "$backup_root_dir" "$subgroup_id" "$parent_dir"
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
    rclone --config /tmp/rclone.conf copy "${zip_destination_dir}/gitlab_backup_group_${group_id}_${date_and_time}.zip" "s3:${rclone_bucket}/gitlab/gitlab-backup_${group_id}_${date_and_time}"
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

  curl -s --request PUT "$api_url" \
      -H "PRIVATE-TOKEN: $GLOBAL_GIT_TOKEN" \
      -H "Content-Type: application/json" \
      --data "{
          \"branch\": \"${branch_name}\",
          \"author_email\": \"$GLOBAL_GIT_EMAIL\",
          \"author_name\": \"$GLOBAL_GIT_USER\",
          \"content\": $json_safe_contents,
          \"commit_message\": \"${commit_message}\"
      }" # > /dev/null 2>&1
}

function git_set_remote() {
  if [ "$#" -ne 2 ]; then
    echo "Usage: set_git_remote <repo_url> <token>"
    echo "  <repo_url>: The URL of the repository where you want to change the remote (e.g., https://github.com/username/new-repository.git)"
    echo "  <token>: Your personal access token for authentication"
    return 1
  fi

  local repo_url=$1
  local token=$2

  # Check if the URL has 'https://' at the start and strip it out because we'll add it along with the token
  if [[ $repo_url =~ ^https:// ]]; then
    repo_url="${repo_url#https://}"
  fi

  # Construct the new URL with the token
  local new_url="https://${token}@${repo_url}"

  # Set the new URL to the Git remote named 'origin'
  git remote set-url origin "$new_url"
  echo "Remote URL set to ${new_url}"
}

function github_backup() {

  export GIT_TERMINAL_PROMPT=0          # never prompt for username/pw

  ##################################################################
  # helpers
  ##################################################################
  _clone_branches() {                    # $1 remote  $2 dest dir
      local remote=$1 dest=$2
      git ls-remote --heads "$remote" | awk '{print $2}' | sed 's#refs/heads/##' |
      while read -r br; do
          local safe=${br//[\/:]/_}
          mkdir -p "$dest/$safe"
          git clone --quiet --branch "$br" --single-branch "$remote" "$dest/$safe" \
               >/dev/null 2>&1 || _dbg "git clone failed on branch $br"
      done
  }

  _paged_json() {                        # $1 endpoint-without-?  $2 outfile
      local ep=$1 out=$2 page=1 buf='[]'
      while : ; do
          local url="${ep}?per_page=100&page=${page}"
          _dbg "GET  $url"
          local rsp; rsp=$(curl -s -w "%{http_code}" -H "Authorization: token $github_token" "$url")
          local code=${rsp: -3} body=${rsp::-3}
          _dbg "HTTP $code  body preview: $(echo "$body" | head -c120 | tr '\n' ' ')…"

          [[ "$code" != "200" ]] && { _dbg "non-200, stop paging"; break; }
          [[ "$(echo "$body" | jq -r 'type')" != "array" ]] && { _dbg "payload not array, stop paging"; break; }

          [[ "$(echo "$body" | jq 'length')" -eq 0 ]] && break
          buf=$(jq -s 'add' <(echo "$buf") <(echo "$body"))
          ((page++))
      done
      [[ "$(echo "$buf" | jq 'length')" -gt 0 ]] && printf '%s' "$buf" > "$out"
  }

  ##################################################################
  # prompts
  ##################################################################
  : "${github_token:=$(read -rp 'GitHub Personal Access Token: ' t && echo "$t")}"
  : "${github_user:=$(read -rp 'GitHub username / org: ' u && echo "$u")}"
  : "${REPO_SCOPE:=owner}"
  local ts; ts=$(date +%Y-%m-%d_%H-%M-%S)

  ##################################################################
  # destination dirs
  ##################################################################
  if [[ -z ${backup_dir:-} ]]; then
      root="/tmp/backup/files"; zip_dir="/tmp/backup/zip"
  else
      case "$backup_dir" in
          "/"|"/mnt"|"/home"|"/root"|"/etc"|"/var"|"/usr"|"/bin"|"/sbin"|"/lib"|"/lib64"|"/opt")
              echo "ERR: backup_dir cannot be critical"; return 1 ;;
          *)  root="$backup_dir/files"; zip_dir="$backup_dir/zip" ;;
      esac
  fi
  mkdir -p "$root"

  ##################################################################
  # decide user vs org endpoint
  ##################################################################
  local api
  if curl -sI "https://api.github.com/orgs/$github_user" | grep -q '^Status: 200'; then
      api="https://api.github.com/orgs/$github_user/repos"
      [[ -z "$REPO_SCOPE" ]] && REPO_SCOPE=all
  else
      api="https://api.github.com/users/$github_user/repos"
  fi

  ##################################################################
  # iterate repo pages
  ##################################################################
  local page=1
  while : ; do
      local url="${api}?type=${REPO_SCOPE}&per_page=100&page=${page}"
      _dbg "LIST $url"
      local rsp; rsp=$(curl -s -w "%{http_code}" -H "Authorization: token $github_token" "$url")
      local code=${rsp: -3} body=${rsp::-3}
      _dbg "HTTP $code  body preview: $(echo "$body" | head -c120 | tr '\n' ' ')…"

      [[ "$code" != "200" ]] && { _dbg "non-200, stop repo pagination"; break; }
      [[ "$(echo "$body" | jq -r 'type')" != "array" ]] && { _dbg "payload not array, stop"; break; }
      [[ "$(echo "$body" | jq 'length')" -eq 0 ]] && break

      echo "$body" | jq -c '.[]' | while read -r repo_raw; do
          if [[ "$(echo "$repo_raw" | jq -r 'type')" != "object" ]]; then
              _dbg "⚠️  skipping non-object entry: $repo_raw"; continue
          fi
          local full; full=$(echo "$repo_raw" | jq -r '.full_name')
          echo "➡  $full"

          local remote="https://${github_token}@github.com/${full}.git"
          local repo_dir="$root/_repositories/$full"
          local mir_dir="$root/_mirror/$full"
          mkdir -p "$repo_dir" "$mir_dir"

          _clone_branches "$remote" "$repo_dir"
          git clone --quiet --mirror "$remote" "$mir_dir" >/dev/null 2>&1 || \
              _dbg "mirror clone failed $full"

          # -------- metadata ---------------------------------------------
          local m="$root/_metadata/$full"; mkdir -p "$m"
          curl -s -H "Authorization: token $github_token" \
               "https://api.github.com/repos/$full" > "$m/repo.json"

          for ep in issues pulls; do
              _paged_json "https://api.github.com/repos/$full/${ep}?state=all" "$m/${ep}.json"
          done
          [[ -s "$m/issues.json" ]] && jq -c '.[]' "$m/issues.json" |
              while read -r i; do
                  _paged_json "https://api.github.com/repos/$full/issues/$(echo "$i" | jq -r '.number')/comments" \
                              "$m/issue_$(echo "$i" | jq -r '.number')_comments.json"
              done
          [[ -s "$m/pulls.json" ]] && jq -c '.[]' "$m/pulls.json" |
              while read -r p; do
                  local num; num=$(echo "$p" | jq -r '.number')
                  _paged_json "https://api.github.com/repos/$full/pulls/$num/reviews"  "$m/pr_${num}_reviews.json"
                  _paged_json "https://api.github.com/repos/$full/pulls/$num/comments" "$m/pr_${num}_comments.json"
              done
          _paged_json "https://api.github.com/repos/$full/releases" "$m/releases.json"

          # -------- wiki --------------------------------------------------
          if git ls-remote --exit-code --heads "https://github.com/${full}.wiki.git" >/dev/null 2>&1; then
              local w="$root/_wiki/$full"; mkdir -p "$w"
              git clone --quiet --mirror "https://${github_token}@github.com/${full}.wiki.git" "$w" \
                   >/dev/null 2>&1 || _dbg "wiki clone failed $full"
          fi
      done
      ((page++))
  done

  ##################################################################
  # archive + cleanup
  ##################################################################
  echo "Zipping …"
  mkdir -p "$zip_dir"
  local zip="$zip_dir/github_backup_${github_user}_${ts}.zip"
  (cd "$root" && zip -q -r "$zip" . -x '*.zip')
  find "$root" -mindepth 1 -delete

  [[ -n ${rclone_bucket:-} ]] && \
      rclone --config /tmp/rclone.conf copy "$zip" "s3:${rclone_bucket}/github/$(basename "$zip")"

  echo "✅  GitHub backup ready → $zip"
}
