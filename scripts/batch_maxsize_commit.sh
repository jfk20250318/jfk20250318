#!/usr/bin/env bash
# git_batch_commit.sh
# Batch-commits untracked Git files under ./pdf/ into <=1GB commits with consistent message and branch.
# Supports --dry-run to preview batches without committing.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

function main() {
  local -r max_size_bytes=$((1024 * 1024 * 1024))  # 1 GB
  local -r commit_message='new tranche 1900h 20250403'
  local -r branch='main'
  local dry_run='false'

  if [[ "${1:-}" == '--dry-run' ]]; then
    dry_run='true'
    shift
  elif [[ $# -gt 0 ]]; then
    log '❌ Unknown argument: %s\n' "${1}"
    exit 1
  fi

  open_log
  process_untracked_files "${max_size_bytes}" "${commit_message}" "${branch}" "${dry_run}"
  close_log
}

function open_log() {
  exec 5>>"/tmp/git_batch_commit.log"
}

function close_log() {
  exec 5>&-
}

function log() {
  if [[ $# -eq 0 ]]; then
    printf '\n' | tee -a /dev/fd/5
  else
    printf "$@" | tee -a /dev/fd/5
  fi
}

function process_untracked_files() {
  local -r max_size_bytes="${1}"
  local -r commit_message="${2}"
  local -r branch="${3}"
  local -r dry_run="${4}"

  local all_files
  all_files=$(git ls-files --others --exclude-standard -- pdf || true)

  if [[ -z "${all_files}" ]]; then
    log '✅ No untracked files under ./pdf to commit.\n'
    return
  fi

  iterate_and_batch_files "${all_files}" "${max_size_bytes}" "${commit_message}" "${branch}" "${dry_run}"
  log '🎉 All files processed and committed in batches.\n'
}

function iterate_and_batch_files() {
  local -r all_files="${1}"
  local -r max_size_bytes="${2}"
  local -r commit_message="${3}"
  local -r branch="${4}"
  local -r dry_run="${5}"

  local current_size=0
  local file_list=()
  local file

  while IFS= read -r file; do
    if should_skip_file "${file}"; then
      continue
    fi

    local size
    size=$(get_file_size "${file}")

    if should_flush_batch "${current_size}" "${size}" "${max_size_bytes}" "${#file_list[@]}"; then
      flush_and_report_batch "${commit_message}" "${branch}" "${current_size}" "${dry_run}" "${file_list[@]}"
      file_list=()
      current_size=0
    fi

    file_list+=("${file}")
    current_size=$((current_size + size))
  done <<< "${all_files}"

  if [[ ${#file_list[@]} -gt 0 ]]; then
    flush_and_report_batch "${commit_message}" "${branch}" "${current_size}" "${dry_run}" "${file_list[@]}"
  fi
}

function should_skip_file() {
  local -r file="${1}"
  [[ ! -f "${file}" ]]
}

function get_file_size() {
  local -r file="${1}"
  stat -f%z "${file}"
}

function should_flush_batch() {
  local -r current="${1}"
  local -r next="${2}"
  local -r max="${3}"
  local -r count="${4}"
  [[ $((current + next)) -gt ${max} && ${count} -gt 0 ]]
}

function flush_and_report_batch() {
  local -r commit_message="${1}"
  local -r branch="${2}"
  local -r total_size="${3}"
  local -r dry_run="${4}"
  shift 4
  local files=("${@}")

  log_batch_summary "${total_size}" "${files[@]}"

  if [[ "${dry_run}" == 'true' ]]; then
    log '🧪 Dry run: would commit %d files to "%s"\n\n' "${#files[@]}" "${branch}"
  else
    commit_file_batch "${commit_message}" "${branch}" "${files[@]}"
  fi
}

function log_batch_summary() {
  local -r total_size="${1}"
  shift
  local files=("${@}")
  local size_mb
  size_mb=$(format_bytes_mb "${total_size}")

  log '📦 New batch: %d files, total size: %s MB\n' "${#files[@]}" "${size_mb}"

  local file
  for file in "${files[@]}"; do
    log '  - %s\n' "${file}"
  done
}

function commit_file_batch() {
  local -r message="${1}"
  local -r branch="${2}"
  shift 2
  local files=("${@}")

  git add "${files[@]}"
  git commit -s -S -m "${message}"
  git push origin "${branch}"

  log '🚀 Committed and pushed %d files to "%s"\n' "${#files[@]}" "${branch}"
}

function format_bytes_mb() {
  local -r bytes="${1}"
  local -r mb=$(( (bytes + 524288) / 1048576 ))
  printf "%'d" "${mb}"
}

main "$@"
