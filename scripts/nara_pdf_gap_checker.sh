#!/usr/bin/env bash
# nara_pdf_gap_checker.sh
# Two-phase NARA PDF checker:
# Phase 1: Detect gaps in sequential filenames
# Phase 2: Check which missing files exist remotely

# bash configuration:
set -o nounset
set -o errexit
set -o pipefail

declare -r LOG_DIR="./logs"
declare -r BASE_URL="https://www.archives.gov/files/research/jfk/releases/2025/0318/"
declare RUN_TS
RUN_TS="$(date '+%Y%m%d_%H%M%S')"
declare -r OUTPUT_MISSING="${LOG_DIR}/missing_files_${RUN_TS}.txt"
declare -r OUTPUT_FOUND="${LOG_DIR}/found_files_${RUN_TS}.txt"
declare -r OUTPUT_EXCEPTIONS="${LOG_DIR}/exceptions_${RUN_TS}.txt"
declare -r LOGFILE="${LOG_DIR}/logfile_${RUN_TS}.txt"
declare DRY_RUN=false
declare GAPS_ONLY=false

function main() {
  function_validate_arguments "$@"
  function_prepare_log_dir
  function_setup_logging
  function_initialize_outputs
  function_phase_one "$1"
  if [[ "${DRY_RUN}" == false && "${GAPS_ONLY}" == false ]]; then
    function_phase_two
  elif [[ "${DRY_RUN}" == true ]]; then
    function_log "🚩 Dry run enabled; skipping remote checks."
  fi
  function_cleanup_and_summarize
}

function function_prepare_log_dir() {
  mkdir -p "${LOG_DIR}"
}

function function_setup_logging() {
  exec 5>"${LOGFILE}"
  if [[ "${GAPS_ONLY}" == false ]]; then
    function_log "📄 Logfile initialized: ${LOGFILE}"
  fi
}

function function_initialize_outputs() {
  : > "${OUTPUT_MISSING}"
  : > "${OUTPUT_FOUND}"
  : > "${OUTPUT_EXCEPTIONS}"
}

function function_phase_one() {
  local scan_root="$1"
  if [[ "${GAPS_ONLY}" == false ]]; then
    function_log "🔎 Scanning for PDF files under: ${scan_root}"
  fi
  local all_files
  all_files="$(find "${scan_root}" -type f -name '*.pdf')"

  if [[ -z "${all_files}" ]]; then
    function_log '❌ No PDF files found. Exiting.'
    exit 1
  fi

  if [[ "${GAPS_ONLY}" == false ]]; then
    function_log '📂 Sorting files by filename...'
  fi

  local sorted_tmp
  sorted_tmp="$(mktemp)"
  function_generate_sorted_list_by_basename "${all_files}" > "${sorted_tmp}"

  if [[ "${GAPS_ONLY}" == false ]]; then
    function_log '🔍 Phase 1: Identifying missing files...'
  fi

  function_identify_missing_files "${sorted_tmp}"
  export SORTED_TMP_FILE="${sorted_tmp}"
}

function function_phase_two() {
  function_log '🌐 Phase 2: Checking which missing files exist remotely...'
  function_verify_missing_files_exist
}

function function_cleanup_and_summarize() {
  rm -f "${SORTED_TMP_FILE}"
  function_summarize_outputs
}

function function_log() {
  local message="$1"
  printf '%s\n' "${message}" | tee -a /dev/fd/5
}

function function_generate_sorted_list_by_basename() {
  local input="$1"
  printf '%s\n' "${input}" | awk -F/ '{print $NF, $0}' | sort | awk '{ $1=""; sub(/^ /, ""); print }'
}

function function_identify_missing_files() {
  local filelist="$1"
  local prev=""
  local file
  while IFS= read -r file || [[ -n "${file}" ]]; do
    function_process_file_for_gaps "${file}" "${prev}"
    prev="${file}"
  done < "${filelist}"
}

function function_process_file_for_gaps() {
  local file="$1"
  local prev="$2"

  if ! function_is_valid_nara_filename "${file}"; then
    if [[ "${GAPS_ONLY}" == false ]]; then
      function_log "⚠️ Skipping invalid: $(basename "${file}")"
    fi
    printf '%s\n' "${file}" >> "${OUTPUT_EXCEPTIONS}"
    return
  fi

  if [[ -n "${prev}" ]]; then
    function_compare_adjacent_files "${prev}" "${file}"
  fi
}

function function_is_valid_nara_filename() {
  local filepath="$1"
  local filename
  filename="$(basename "${filepath}")"
  local base="${filename%.pdf}"
  base="${base%%_*}"
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
    return
  fi

  local page_count
  page_count="$(function_get_pdf_page_count "${file1}")"

  local expected_start=$((10#${page1} + page_count))
  local expected_end=$((10#${page2} - 1))

  if (( expected_start <= expected_end )); then
    function_log "📎 Gap after $(basename "${file1}"): ${expected_start} to ${expected_end}"
    function_write_missing_range "${prefix1}" "${expected_start}" "${expected_end}"
  fi
}

function function_write_missing_range() {
  local prefix="$1"
  local start_page="$2"
  local end_page="$3"
  local i
  for ((i = start_page; i <= end_page; i++)); do
    printf '%s\n' "${prefix}${i}.pdf" >> "${OUTPUT_MISSING}"
  done
}

function function_verify_missing_files_exist() {
  local filename
  while IFS= read -r filename || [[ -n "${filename}" ]]; do
    function_check_and_record_remote_file "${filename}"
  done < "${OUTPUT_MISSING}"
}

function function_check_remote_exists() {
  local filename="$1"
  local url="${BASE_URL}${filename}"
  curl --head --silent --fail "${url}" > /dev/null
}

function function_parse_nara_filename() {
  local filepath="$1"
  local filename
  filename="$(basename "${filepath}")"
  local base="${filename%.pdf}"
  base="${base%%_*}"
  local page="${base##*-}"
  local prefix="${base%-"${page}"}-"
  printf '%s %s\n' "${prefix}" "${page}"
}

function function_get_pdf_page_count() {
  local file="$1"
  local count
  count="$(command pdfinfo "${file}" 2>/dev/null | grep '^Pages:' | awk '{print $2}' || true)"
  printf '%s\n' "${count:-0}"
}

function function_validate_arguments() {
  if [[ $# -lt 1 ]]; then
    printf '❌ ERROR: You must supply the scan root directory as the first argument.' >&2
    exit 1
  fi
  if [[ ! -d "$1" ]]; then
    printf '❌ ERROR: Directory not found: %s' "$1" >&2
    exit 1
  fi
  for arg in "$@"; do
    [[ ${arg} == "--dry-run" ]] && DRY_RUN=true
    [[ ${arg} == "--gaps-only" ]] && GAPS_ONLY=true
  done
}

function function_summarize_outputs() {
  function_log "✅ Gap check completed. Results logged."
}

main "$@"
