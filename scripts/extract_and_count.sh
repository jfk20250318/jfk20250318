#!/usr/bin/env bash
# extract_and_count.sh
# Extracts and merges text from one or more PDFs and generates a CSV word count file
# for words longer than 2 characters and fewer than 10% diacritical characters.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

function main() {
  setup_logging
  check_darwin
  validate_arguments "${@:-}"
  run_extraction_and_count "$@"
  log '✅ All tasks completed successfully.\n'
}

function setup_logging() {
  mkdir -p ./logs
  local -r timestamp="$(date '+%Y%m%d-%H%M%S')"
  local -r log_file="./logs/extract_and_count-${timestamp}.log"
  exec 5>&1
  exec > >(tee "${log_file}") 2>&1
}

function run_extraction_and_count() {
  local input_glob="$1"
  local output_txt="$2"
  local word_count_file="$3"

  local temp_txt
  temp_txt="$(mktemp)"
  : > "${temp_txt}"

  process_multiple_pdfs_parallel "${input_glob}" "${temp_txt}"

  log '📝 Generating final output: %s\n' "${output_txt}"
  cp "${temp_txt}" "${output_txt}"
  log_file_line_count "${output_txt}"

  log '📊 Starting word count on merged text...\n'
  generate_word_count "${output_txt}" "${word_count_file}"
  log_file_line_count "${word_count_file}"

  rm -f "${temp_txt}"
}

function log() {
  printf "$1" "${@:2}" >&5
}

function check_darwin() {
  local -r kernel_name="$(uname -s)"
  if [[ "${kernel_name}" != 'Darwin' ]]; then
    log '⚠️ This script is designed for macOS (Darwin).\n'
    exit 1
  fi
}

function validate_arguments() {
  check_argument_count "$@"
  check_non_empty_arguments "$@"
  check_matching_files "$1"
}

function check_argument_count() {
  if [[ $# -ne 3 ]]; then
    log '❌ Error: Incorrect number of arguments.\n'
    log 'Usage: %s <input_glob> <output_text.txt> <word_count.csv>\n' "$0"
    exit 1
  fi
}

function check_non_empty_arguments() {
  local input_glob="$1"
  local output_txt="$2"
  local word_count_file="$3"

  if [[ -z "${input_glob}" || -z "${output_txt}" || -z "${word_count_file}" ]]; then
    log '❌ Error: Arguments cannot be empty.\n'
    exit 1
  fi
}

function check_matching_files() {
  local input_glob="$1"
  local matching_files
  matching_files=$(find . -type f -name "$(basename "${input_glob}")" || true)

  if [[ -z "${matching_files}" ]]; then
    log '❌ Error: No input files match the pattern: %s\n' "${input_glob}"
    exit 1
  fi

  log '📄 Matching input files:\n'
  printf '%s\n' ${matching_files} | while read -r file; do log '  - %s\n' "${file}"; done
}

function process_multiple_pdfs_parallel() {
  local input_glob="$1"
  local merged_txt="$2"

  local -a files=()
  while IFS= read -r file; do
    files+=("${file}")
  done < <(find . -type f -name "$(basename "${input_glob}")" | sort -V)

  temp_dir="$(mktemp -d)"

  launch_parallel_extractions "${temp_dir}" "${files[@]}"
  merge_extracted_texts "${temp_dir}" "${merged_txt}"
  rm -rf "${temp_dir}"
}

function launch_parallel_extractions() {
  log '🚀 Starting parallel text extraction with up to %s jobs
' "$(sysctl -n hw.ncpu)"
  local temp_dir="$1"
  shift
  local files=("$@")

  local max_jobs
  max_jobs=$(sysctl -n hw.ncpu)
  local job_count=0
  local -a pids

  for pdf_file in "${files[@]}"; do
    local temp_extract
    temp_extract="${temp_dir}/$(basename "${pdf_file}").txt"

    log '⏱️ Queuing extraction for: %s
' "${pdf_file}"
    extract_text "${pdf_file}" "${temp_extract}" &
    pids+=($!)
    job_count=$((job_count + 1))

    if [[ ${job_count} -ge ${max_jobs} ]]; then
      wait -n
      job_count=$((job_count - 1))
    fi
  done
  wait
}

function merge_extracted_texts() {
  local temp_dir="$1"
  local merged_txt="$2"

  for txt in "${temp_dir}"/*.txt; do
    log_file_line_count "${txt}"
    cat "${txt}" >> "${merged_txt}"
  done
}

function log_file_line_count() {
  local file="$1"
  if [[ -f "${file}" ]]; then
    local line_count
    line_count=$(wc -l < "${file}")
    log '📏 File %s has %s lines\n' "${file}" "${line_count}"
  fi
}

function extract_text() {
  local input_pdf="$1"
  local output_txt="$2"

  if command -v pdftotext >/dev/null 2>&1; then
    log '🔍 Using pdftotext for: %s\n' "${input_pdf}"
    run_pdftotext "${input_pdf}" "${output_txt}"
  elif command -v ocrmypdf >/dev/null 2>&1; then
    log '🖨️ Using ocrmypdf for OCR: %s\n' "${input_pdf}"
    run_ocrmypdf "${input_pdf}" "${output_txt}"
  else
    log '❌ Error: Neither pdftotext nor ocrmypdf is available.\n'
    exit 1
  fi
}

function run_pdftotext() {
  local input_pdf="$1"
  local output_txt="$2"

  pdftotext "${input_pdf}" "${output_txt}"
  log '✅ Extracted text via pdftotext.\n'
}

function run_ocrmypdf() {
  local input_pdf="$1"
  local output_txt="$2"

  ocrmypdf --sidecar "${output_txt}" "${input_pdf}" /dev/null
  log '✅ OCR completed via ocrmypdf.\n'
}

function convert_to_utf8() {
  local input_file="$1"
  local output_file="$2"
  iconv -f UTF-8 -t UTF-8 -c "${input_file}" > "${output_file}"
}

function count_filtered_words() {
  local input_file="$1"
  local tmpfile="$2"
  awk -f "$(dirname "$0")/extract_and_count.awk" "${input_file}" | sort -k1,1nr -k2 > "${tmpfile}"
}

function generate_word_count() {
  local input_txt="$1"
  local output_file="$2"
  local tmpfile utf8_file

  tmpfile="$(mktemp)"
  utf8_file="$(mktemp)"

  log '🧹 Normalizing encoding and filtering...\n'
  convert_to_utf8 "${input_txt}" "${utf8_file}"
  count_filtered_words "${utf8_file}" "${tmpfile}"

  write_csv_header "${output_file}"
  cat "${tmpfile}" >> "${output_file}"
  rm -f "${tmpfile}" "${utf8_file}"

  log '✅ Word count CSV saved: %s\n' "${output_file}"
}

function write_csv_header() {
  local output_file="$1"
  printf 'count,word\n' > "${output_file}"
}

main "${@:-}"
