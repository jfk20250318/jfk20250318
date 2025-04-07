#!/usr/bin/env bash
# pdf_mod_dates.sh
# List relative path and internal PDF modification date (in ISO 8601 format) for each PDF under the given root directory.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

# Main entry point
function main() {
  initialize_logging
  validate_args "${@:-}"
  process_all_pdfs "${1}"
  log '✅ Done listing PDF modification dates.'
}

# Initialize log file and FD 5
function initialize_logging() {
  local -r log_dir="./logs"
  local timestamp
  timestamp=$(date '+%Y%m%d_%H%M%S')
  log_file="${log_dir}/pdf_mod_dates_${timestamp}.log"
  mkdir -p "${log_dir}"
  exec 5> >(tee -a "${log_file}")

  log "📝 Log file initialized at ${log_file}"
}

# Centralized logging function
function log() {
  printf '%s\n' "${*}" >&5
}

# Usage info
function usage() {
  log 'Usage: pdf_mod_dates.sh <root_directory>'
  log 'Example: pdf_mod_dates.sh ./archives'
}

# Validate arguments
function validate_args() {
  if [[ ${#} -ne 1 ]]; then
    usage
    exit 1
  fi

  local -r root="${1}"
  if [[ -z "${root}" || ! -d "${root}" ]]; then
    log "❌ Error: Directory not found or empty: '${root}'"
    usage
    exit 1
  fi
}

# Reusable function to emit all PDF files under the root
function get_pdf_files() {
  local -r root_dir="${1}"
  find "${root_dir}" -type f -name '*.pdf' -print0
}

# Process and log the modification date for a single PDF file
function print_pdf_mod_date() {
  local -r file="${1}"
  local raw_date
  raw_date=$(exiftool -s -s -s -ModifyDate "${file}" 2>/dev/null || printf '')

  local iso_date
  if [[ -n "${raw_date}" ]]; then
    iso_date=$(date -j -f '%Y:%m:%d %H:%M:%S%z' "${raw_date}" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || printf '')
    if [[ -z "${iso_date}" ]]; then
      iso_date=$(date -j -f '%Y:%m:%d %H:%M:%S' "${raw_date}" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || printf '')
    fi
    if [[ -z "${iso_date}" ]]; then
      iso_date='INVALID_DATE'
    fi
  else
    iso_date='N/A'
  fi

  log "${file}\t${iso_date}"
}

# Process all found PDF files
function process_all_pdfs() {
  local -r search_dir="${1}"
  log "🔍 Searching for PDF files under: ${search_dir}"

  get_pdf_files "${search_dir}" | while IFS= read -r -d '' file; do
    print_pdf_mod_date "${file}"
  done
}

main "${@:-}"
