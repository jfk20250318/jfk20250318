#!/usr/bin/env bash

function main() {
  local max_size_bytes=$(1024 * 1024 * 1024)  # 1 GB per commit
  local commit_message="new tranche 2230h 20250318"
  local branch="main"

  validate_args "$@"
  process_untracked_files "${max_size_bytes}" "${commit_message}" "${branch}"
}

function validate_args() {
  if [[ $# -ne 0 ]]; then
    log '❌ This script takes no arguments.\n' >&2
    exit 1
  fi
}

function log() {
  if [[ $# -eq 0 ]]; then
    printf '\n' | tee -a "/tmp/git_batch_commit.log"
  else
    printf '%s\n' "$@" | tee -a "/tmp/git_batch_commit.log"
  fi
}

function process_untracked_files() {
  local max_size_bytes="${1}"
  local commit_message="${2}"
  local branch="${3}"

  local all_files
  all_files=$(git ls-files --others --exclude-standard)

  if [[ -z "${all_files}" ]]; then
    log '✅ No untracked files to commit.\n'
    return
  fi

  iterate_and_batch_files "${all_files}" "${max_size_bytes}" "${commit_message}" "${branch}"
  log '🎉 All files processed and committed in batches.\n'
}

function iterate_and_batch_files() {
  local file_list=()
  local current_size=0
  local all_files="${1}"
  local max_size_bytes="${2}"
  local commit_message="${3}"
  local branch="${4}"

  while IFS= read -r file; do
    handle_single_file "${file}" "${max_size_bytes}" "${commit_message}" "${branch}" current_size file_list
  done <<< "${all_files}"

  flush_remaining_files "${commit_message}" "${branch}" "${current_size}" file_list
}

function handle_single_file() {
  local file="${1}"
  local max_size_bytes="${2}"
  local commit_message="${3}"
  local branch="${4}"
  local -n current_size_ref="${5}"
  local -n file_list_ref="${6}"

  if should_skip_file "${file}"; then
    return
  fi

  local size
  size=$(get_file_size "${file}")

  if should_flush_batch "${current_size_ref}" "${size}" "${max_size_bytes}" "${#file_list_ref[@]}" ; then
    flush_and_commit_batch "${file_list_ref[@]}" "${current_size_ref}" "${commit_message}" "${branch}"
    file_list_ref=()
    current_size_ref=0
  fi

  file_list_ref+=("${file}")
  current_size_ref=$((current_size_ref + size))
}

function flush_remaining_files() {
  local commit_message="${1}"
  local branch="${2}"
  local current_size="${3}"
  local -n file_list_ref="${4}"

  if [[ ${#file_list_ref[@]} -gt 0 ]]; then
    flush_and_commit_batch "${file_list_ref[@]}" "${current_size}" "${commit_message}" "${branch}"
  fi
}

function should_skip_file() {
  local file="${1}"
  [[ ! -f "${file}" ]]
}

function get_file_size() {
  local file="${1}"
  stat -f%z "${file}"
}

function should_flush_batch() {
  local current="${1}"
  local next="${2}"
  local max="${3}"
  local count="${4}"
  [[ $((current + next)) -gt ${max} && ${count} -gt 0 ]]
}

function flush_and_commit_batch() {
  local files=("${@:1:$#-3}")
  local total_size="${@: -3:1}"
  local message="${@: -2:1}"
  local branch="${@: -1}"

  log_batch_summary "${total_size}" "${files[@]}"
  commit_file_batch "${message}" "${branch}" "${files[@]}"
}

function log_batch_summary() {
  local total_size="${1}"
  shift
  local files=("$@")
  local size_mb
  size_mb=$(format_bytes_mb "${total_size}")

  printf -v summary '📦 New batch: %d files, total size: %s MB\n' "${#files[@]}" "${size_mb}"
  log "${summary}"

  for file in "${files[@]}"; do
    printf -v line '  - %s\n' "${file}"
    log "${line}"
  done
}

function commit_file_batch() {
  local message="${1}"
  local branch="${2}"
  shift 2
  local files=("$@")

  git add "${files[@]}"
  git commit -s -S -m "${message}"
  git push origin "${branch}"

  printf -v done_msg '🚀 Committed and pushed %d files to '\''%s'\''\n' "${#files[@]}" "${branch}"
  log "${done_msg}"
}

function format_bytes_mb() {
  local bytes="${1}"
  local mb=$(( (bytes + 524288) / 1048576 ))
  printf "%'d" "${mb}"
}

main "$@"

