#!/bin/bash

#
# Render the Jira Ticket from the given branch.
#
# Eg: Given branch "feat/TEAM-123-foo-bar" should return `TEAM-123`
#
function normalize_ticket() {
  local gitBranch=$1
  # shellcheck disable=SC2046
  # shellcheck disable=SC2005
  echo "$gitBranch" |
    grep -Eo '^(\w+\/)?(\w+-)?(\w+[-_])?[0-9]+' |
    grep -Eo '(\w+[-])?[0-9]+' |
    tr "[:lower:]" "[:upper:]"
}

#
# Render the branch key.
#
# Eg: Given branch "feat/TEAM-123-foo-bar" should return `feat`
#
function normalize_key() {
  local gitBranch=$1
  local commitMsg=$2

  # Check if starts with a string before ':'
  # In such a case, the sanitizedMsg overrides the actual git branch
  if [[ $commitMsg =~ ^([^:]+): ]]; then
    echo "${BASH_REMATCH[1]}"
    return
  fi

  local branchKey
  branchKey=$(echo "$gitBranch" | cut -d'/' -f1 | tr "[:upper:]" "[:lower:]")

  local original_branch
  original_branch="$(echo "$gitBranch" | tr "[:upper:]" "[:lower:]")"

  if [[ "$branchKey" == "$original_branch" ]]; then
    branchKey=$DEFAULT_BRANCH_KEY
  fi

  case "$branchKey" in
    "task" | "feature" | "story")
      branchKey="feat"
    ;;
    "bug" | "bugfix")
      branchKey="fix"
    ;;
    *)
      # Only if the branchKey is empty then use feat by default.
      # Otherwise, the key commit contains the following structural elements,
      # to communicate intent to the consumers of your library.
      # @see: https://www.conventionalcommits.org/en/v1.0.0/#summary
      if [ -z "$branchKey" ]; then
        branchKey="feat"
      fi
    ;;
  esac

  echo $branchKey
}

#
# Render the scope from commit if exists. Empty otherwise.
#
# Eg: Given a sanitizedMsg "(scope) foo bar" should return `(scope)`
#
function normalize_scope() {
  local commitMsg=$1
  echo "$commitMsg" |
    sed -n 's/^[!(]*\(([^)]*)\).*/\1/p' |
    tr "[:upper:]" "[:lower:]"
}

#
# Render the commit following the "conventional commits" pattern.
#
# @see: https://www.conventionalcommits.org/
#
function render_message() {
  local commitMsg=$1
  local branchKey=$2
  local commitScope=$3
  local jiraTicket=$4

  if [[ "$DEBUG" == true ]]; then
    echo "commitMsg = $commitMsg"
    echo "branchKey = $branchKey"
    echo "commitScope = $commitScope"
    echo "jiraTicket = $jiraTicket"
  fi

  local breakingChange="${commitMsg:0:1}"
  if [ "$breakingChange" == "!" ]; then
    commitMsg="${commitMsg:1}"
  else
    breakingChange=''
  fi

  local msgWithoutScope="${commitMsg/$commitScope}"
  local sanitizedMsg="${msgWithoutScope#*:}"
  sanitizedMsg="${sanitizedMsg#"${sanitizedMsg%%[![:space:]]*}"}"

  if [[ $jiraTicket != '' ]]; then
    echo "${branchKey}${commitScope}${breakingChange}: [$jiraTicket] $sanitizedMsg"
  else
    echo "${branchKey}${commitScope}${breakingChange}: $sanitizedMsg"
  fi
}

function check_conventional_commit() {
  local commitMsg=$1
  readonly COMMIT_MSG_REGEX="^[^:]+: \[[[:alnum:]-]+\] .+$"

  if [[ "$commitMsg" =~ $COMMIT_MSG_REGEX ]]; then
    if [[ "$DEBUG" == true ]]; then
      echo "sanitizedMsg = $sanitizedMsg"
      echo "The commit sanitizedMsg is already a conventional commit: ignoring the hook."
    fi

    exit 0;
  fi
}

function render_result() {
  local updated_msg=$1
  local file=$2

  if [[ "$TEST" == true ]]; then
    echo "$updated_msg"
  else
    echo "$updated_msg" > "$file"
  fi
}

##################
###### MAIN ######
##################

# Useful for local testing and debugging. Usage:
# TEST=true ./git-hooks/prepare-commit-msg.sh
set -ueo pipefail

exec </dev/tty

ORIGINAL_FILE="$1"
COMMIT_SOURCE="$2"
ORIGINAL_MSG="$(cat ${ORIGINAL_FILE})"

# check_conventional_commit "$ORIGINAL_MSG"
# 
# GIT_BRANCH=${TEST_BRANCH:-"$(git rev-parse --abbrev-ref HEAD)")}
DEFAULT_BRANCH_KEY='feat'
BRANCH_KEY=$(normalize_key "$GIT_BRANCH" "$ORIGINAL_MSG")
# COMMIT_SCOPE=$(normalize_scope "$ORIGINAL_MSG")
# JIRA_TICKET=$(normalize_ticket "$GIT_BRANCH")
# 
# UPDATED_MSG=$(render_message "$ORIGINAL_MSG" "$BRANCH_KEY" "$COMMIT_SCOPE" "$JIRA_TICKET")

TYPES=($BRANCH_KEY fix feat build chore ci docs style refactor perf test)
SELECTED_TYPE=

PS3="Select type: "
select typ in "${TYPES[@]}"; do
  SELECTED_TYPE=$typ
  break
done

read -p "Enter Scope if any: " SELECTED_SCOPE

if [[ -n "${SELECTED_SCOPE}" ]]; then
  SELECTED_SCOPE="(${SELECTED_SCOPE})"
fi

read -p "Is this a breaking change [yn]? " BREAKING_CHANGE

case $BREAKING_CHANGE in
  y) BREAKING_CHANGE="!";;
  *) BREAKING_CHANGE="";;
esac

UPDATED_MESSAGE="${SELECTED_TYPE}${SELECTED_SCOPE}${BREAKING_CHANGE}: ${ORIGINAL_MSG}"

read -p "Ready to commit: '${UPDATED_MESSAGE}' [yn]? " READY_TO_COMMIT

case $READY_TO_COMMIT in
  y) echo "$UPDATED_MSG" > "$ORIGINAL_FILE";;
  *) exit 1 ;;
esac

