#!/usr/bin/env bash
# nara_pdf_gap_checker.sh
# Two-phase NARA PDF checker:
# Phase 1: Detect gaps in sequential filenames
# Phase 2: Check which missing files exist remotely

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_DIR="./logs"
declare -r BASE_URL="https://www.archives.gov/files/research/jfk/releases/2025/0318/"
declare RUN_TS
RUN_TS="$(date '+%Y%m%d_%H%M%S')"
declare -r OUTPUT_MISSING="${LOG_DIR}/missing_files_${RUN_TS}.txt"
declare -r OUTPUT_FOUND="${LOG_DIR}/found_files_${RUN_TS}.txt"
declare -r OUTPUT_EXCEPTIONS="${LOG_DIR}/exceptions_${RUN_TS}.txt"
declare -r LOGFILE="${LOG_DIR}/logfile_${RUN_TS}.txt"

#######################################
# Main entry point
# Arguments:
#   $1: scan root directory
#######################################
function main() {
  function_validate_arguments "$@"
  function_prepare_log_dir
  function_setup_logging
  function_initialize_outputs
  function_phase_one "$1"
  function_phase_two
  function_cleanup_and_summarize
}

#######################################
# Ensure logs directory exists
#######################################
function function_prepare_log_dir() {
  mkdir -p "${LOG_DIR}"
}

#######################################
# Setup logging FD
#######################################
function function_setup_logging() {
  exec 5>"${LOGFILE}"
  function_log "📄 Logfile initialized: ${LOGFILE}"
}

#######################################
# Initialize output files
#######################################
function function_initialize_outputs() {
  : > "${OUTPUT_MISSING}"
  : > "${OUTPUT_FOUND}"
  : > "${OUTPUT_EXCEPTIONS}"
}

#######################################
# Phase 1 entry point
#######################################
function function_phase_one() {
  local scan_root="$1"
  function_log "🔎 Scanning for PDF files under: ${scan_root}"
  local all_files
  all_files="$(find "${scan_root}" -type f -name '*.pdf')"

  if [[ -z "${all_files}" ]]; then
    function_log '❌ No PDF files found. Exiting.'
    exit 1
  fi

  function_log '📂 Sorting files by filename...'
  local sorted_tmp
  sorted_tmp="$(mktemp)"
  function_generate_sorted_list_by_basename "${all_files}" > "${sorted_tmp}"

  function_log '🔍 Phase 1: Identifying missing files...'
  function_identify_missing_files "${sorted_tmp}"
  export SORTED_TMP_FILE="${sorted_tmp}"
}

#######################################
# Phase 2 entry point
#######################################
function function_phase_two() {
  function_log '🌐 Phase 2: Checking which missing files exist remotely...'
  function_verify_missing_files_exist
}

#######################################
# Final cleanup and summary
#######################################
function function_cleanup_and_summarize() {
  rm -f "${SORTED_TMP_FILE}"
  function_summarize_outputs
}

#######################################
# Logs a message to terminal and logfile (fd 5)
# Arguments:
#   $1: message
#######################################
function function_log() {
  local message="$1"
  printf '%s\n' "${message}" | tee -a /dev/fd/5
}

#######################################
# Sorts file paths by basename
# Arguments:
#   $1: newline-separated full paths
# Outputs:
#   stdout: sorted full paths
#######################################
function function_generate_sorted_list_by_basename() {
  local input="$1"
  printf '%s\n' "${input}" | awk -F/ '{print $NF, $0}' | sort | awk '{ $1=""; sub(/^ /, ""); print }'
}

#######################################
# Phase 1: Find missing files based on sequential gaps
# Arguments:
#   $1: path to sorted file list
#######################################
function function_identify_missing_files() {
  local filelist="$1"
  local prev=""
  local file
  while IFS= read -r file || [[ -n "${file}" ]]; do
    function_process_file_for_gaps "${file}" "${prev}"
    prev="${file}"
  done < "${filelist}"
}

#######################################
# Processes a single file in the list
# Arguments:
#   $1: current file
#   $2: previous file
#######################################
function function_process_file_for_gaps() {
  local file="$1"
  local prev="$2"

  if ! function_is_valid_nara_filename "${file}"; then
    function_log "⚠️ Skipping invalid: $(basename "${file}")"
    printf '%s\n' "${file}" >> "${OUTPUT_EXCEPTIONS}"
    return
  fi

  if [[ -n "${prev}" ]]; then
    function_compare_adjacent_files "${prev}" "${file}"
  fi
}

#######################################
# Verifies filename format conforms to NARA standard
# Arguments:
#   $1: file path
# Returns:
#   0 if valid, 1 otherwise
#######################################
function function_is_valid_nara_filename() {
  local filepath="$1"
  local filename
  filename="$(basename "${filepath}")"
  local base="${filename%.pdf}"
  local page="${base##*-}"
  local prefix="${base%-"${page}"}"

  if [[ ! "${prefix}" =~ ^[0-9] ]]; then
    return 1
  fi

  if [[ ! "${page}" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  return 0
}

#######################################
# Compares two filenames and identifies page gaps
# Arguments:
#   $1: previous file
#   $2: current file
#######################################
function function_compare_adjacent_files() {
  local file1="$1"
  local file2="$2"

  local parsed1
  parsed1="$(function_parse_nara_filename "${file1}")"
  local parsed2
  parsed2="$(function_parse_nara_filename "${file2}")"

  local prefix1 page1
  read -r prefix1 page1 <<< "${parsed1}"
  local prefix2 page2
  read -r prefix2 page2 <<< "${parsed2}"

  if [[ "${prefix1}" != "${prefix2}" ]]; then
    function_log "🚧 Skipping pair: ${prefix1} ≠ ${prefix2}"
    return
  fi

  local page_count
  page_count="$(function_get_pdf_page_count "${file1}")"

  function_log "🧩 Comparing $(basename "${file1}") (page ${page1}, ${page_count} pages) → $(basename "${file2}") (page ${page2})"

  if [[ ${page_count} -eq 0 ]]; then
    function_log "⚠️ No pages in ${file1}. Skipping."
    return
  fi

  local expected_start=$((10#${page1} + page_count))
  local expected_end=$((10#${page2} - 1))

  if (( expected_start <= expected_end )); then
    function_log "📎 Gap found: ${expected_start} to ${expected_end}"
    function_write_missing_range "${prefix1}" "${expected_start}" "${expected_end}"
  else
    function_log "✅ No gap between files"
  fi
}

#######################################
# Writes list of missing files to output
# Arguments:
#   $1: prefix
#   $2: start page
#   $3: end page
#######################################
function function_write_missing_range() {
  local prefix="$1"
  local start_page="$2"
  local end_page="$3"
  local i
  for ((i = start_page; i <= end_page; i++)); do
    printf '%s\n' "${prefix}${i}.pdf" >> "${OUTPUT_MISSING}"
  done
}

#######################################
# Phase 2: Check remote server for missing files
#######################################
function function_verify_missing_files_exist() {
  local filename
  while IFS= read -r filename || [[ -n "${filename}" ]]; do
    function_check_and_record_remote_file "${filename}"
  done < "${OUTPUT_MISSING}"
}

#######################################
# Checks if a remote file exists and logs it
# Arguments:
#   $1: filename
#######################################
function function_check_and_record_remote_file() {
  local filename="$1"
  if function_check_remote_exists "${filename}"; then
    function_log "🌐 Found remotely: ${filename}"
    printf '%s\n' "${filename}" >> "${OUTPUT_FOUND}"
  fi
}

#######################################
# Extracts prefix and page number from filename
# Arguments:
#   $1: file path
# Outputs:
#   echo "<prefix> <page>"
#######################################
function function_parse_nara_filename() {
  local filepath="$1"
  local filename
  filename="$(basename "${filepath}")"
  local base="${filename%.pdf}"
  local page="${base##*-}"
  local prefix="${base%-"${page}"}-"
  printf '%s %s\n' "${prefix}" "${page}"
}

#######################################
# Uses pdfinfo to get page count
# Arguments:
#   $1: file path
# Outputs:
#   echo page count or 0
#######################################
function function_get_pdf_page_count() {
  local file="$1"

  if [[ ! -f "${file}" ]]; then
    printf '0\n'
    return
  fi

  local count
  count="$(command pdfinfo "${file}" 2>/dev/null | grep '^Pages:' | awk '{print $2}' || true)"

  if [[ -z "${count}" ]]; then
    printf '0\n'
  else
    printf '%s\n' "${count}"
  fi
}

#######################################
# HEAD check to see if remote file exists
# Arguments:
#   $1: filename
# Returns:
#   0 if found, 1 otherwise
#######################################
function function_check_remote_exists() {
  local filename="$1"
  local url="${BASE_URL}${filename}"
  curl --head --silent --fail "${url}" > /dev/null
}

#######################################
# Validate arguments
#######################################
function function_validate_arguments() {
  if [[ $# -lt 1 ]]; then
    printf '❌ ERROR: You must supply the scan root directory as the first argument.' >&2
    exit 1
  fi
  if [[ ! -d "$1" ]]; then
    printf '❌ ERROR: Directory not found: %s' "$1" >&2
    exit 1
  fi
}

#######################################
# Final summary log
#######################################
function function_summarize_outputs() {
  local m
  m="$(wc -l < "${OUTPUT_MISSING}" | tr -d ' ')"
  local f
  f="$(wc -l < "${OUTPUT_FOUND}" | tr -d ' ')"
  local e
  e="$(wc -l < "${OUTPUT_EXCEPTIONS}" | tr -d ' ')"$(wc -l < "${OUTPUT_EXCEPTIONS}" | tr -d ' ')
  function_log "✅ ${m} missing files written to ${OUTPUT_MISSING}"
  function_log "✅ ${f} remote files found in ${OUTPUT_FOUND}"
  function_log "⚠️  ${e} invalid/malformed files listed in ${OUTPUT_EXCEPTIONS}"
}

# Run main
main "${@:-}"
