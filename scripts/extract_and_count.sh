#!/usr/bin/env bash
# extract_and_count.sh
# Extracts text from a PDF and generates a CSV word count file with words longer than 2 characters and fewer than 10% diacritical characters.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

function main() {
  mkdir -p ./logs
  local -r timestamp="$(date '+%Y%m%d-%H%M%S')"
  local -r log_file="./logs/extract_and_count-${timestamp}.log"

  exec 5>&1
  exec > >(tee "${log_file}") 2>&1

  check_darwin
  validate_arguments "${@:-}"
  process_pdf_and_generate_csv "$@"
}

function process_pdf_and_generate_csv() {
  local input_pdf="$1"
  local output_txt="$2"
  local word_count_file="$3"

  log '📂 Processing PDF: %s → Extracting to: %s\n' "${input_pdf}" "${output_txt}"
  extract_text "${input_pdf}" "${output_txt}"

  log '📝 Generating CSV word count file: %s\n' "${word_count_file}"
  generate_word_count "${output_txt}" "${word_count_file}"

  log '✅ Word count saved to: %s\n' "${word_count_file}"
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
  if [[ $# -ne 3 ]]; then
    log '❌ Error: Incorrect number of arguments.\n'
    log 'Usage: %s <input.pdf> <output_text.txt> <word_count.csv>\n' "$0"
    exit 1
  fi

  local input_pdf="$1"
  local output_txt="$2"
  local word_count_file="$3"

  if [[ -z "${input_pdf}" || -z "${output_txt}" || -z "${word_count_file}" ]]; then
    log '❌ Error: Arguments cannot be empty.\n'
    exit 1
  fi

  if [[ ! -f "${input_pdf}" ]]; then
    log '❌ Error: Input PDF file %s does not exist.\n' "${input_pdf}"
    exit 1
  fi
}

function extract_text() {
  local input_pdf="$1"
  local output_txt="$2"

  if command -v pdftotext >/dev/null 2>&1; then
    log '🔍 Extracting text with pdftotext...\n'
    run_pdftotext "${input_pdf}" "${output_txt}"
  elif command -v ocrmypdf >/dev/null 2>&1; then
    log '🖨️ Performing OCR with ocrmypdf...\n'
    run_ocrmypdf "${input_pdf}" "${output_txt}"
  else
    log '❌ Error: Neither pdftotext nor ocrmypdf is installed.\n'
    exit 1
  fi
}

function run_pdftotext() {
  local input_pdf="$1"
  local output_txt="$2"

  pdftotext "${input_pdf}" "${output_txt}"
  log '✅ Text extraction complete.\n'
}

function run_ocrmypdf() {
  local input_pdf="$1"
  local output_txt="$2"

  ocrmypdf --sidecar "${output_txt}" "${input_pdf}" /dev/null
  log '✅ OCR completed successfully.\n'
}

function tokenize_words() {
  sed \
    -e 's|[[:space:]]|\n|g' \
    -e 's|[^[:print:]]||g' \
    -e 'y|ABCDEFGHIJKLMNOPQRSTUVWXYZ|abcdefghijklmnopqrstuvwxyz|' \
    -e 's|[^[:alnum:][:punct:]]||g' \
    -e '/^..$/d'
}

function convert_to_utf8() {
  local input_file="$1"
  local output_file="$2"
  iconv -f UTF-8 -t UTF-8 -c "${input_file}" > "${output_file}"
}

function count_filtered_words() {
  local input_file="$1"
  local tmpfile="$2"
  local word_counter=0

  tokenize_words < "${input_file}" | \
    while read -r word; do
      word_counter=$((word_counter + 1))
      if (( word_counter % 1000 == 0 )); then
        printf 'M' >&5
      fi
      if is_valid_word "${word}"; then
        printf '%s\n' "${word}"
      fi
    done | sort | uniq -c | sort -k1,1nr -k2 > "${tmpfile}"
}

function generate_word_count() {
  local input_txt="$1"
  local output_file="$2"
  local tmpfile utf8_file

  tmpfile="$(mktemp)"
  utf8_file="$(mktemp)"

  log '📊 Filtering and counting words (length > 2, diacritic ratio ≤ 10%%)...\n'

  convert_to_utf8 "${input_txt}" "${utf8_file}"
  count_filtered_words "${utf8_file}" "${tmpfile}"

  write_csv_header "${output_file}"
  awk '{ print $1 "," $2 }' "${tmpfile}" >> "${output_file}"
  rm -f "${tmpfile}" "${utf8_file}"

  log '✅ Word count CSV generated: %s\n' "${output_file}"
}

function is_valid_word() {
  local word="$1"
  local raw_len clean_len threshold

  raw_len="${#word}"
  if [[ "${raw_len}" -le 2 ]]; then
    return 1
  fi

  clean_len=$(LC_CTYPE=C printf '%s' "${word}" | tr -cd 'A-Za-z0-9' | wc -c | tr -d ' ')
  threshold=$((raw_len - raw_len / 10))

  if [[ "${clean_len}" -lt "${threshold}" ]]; then
    return 1
  fi

  return 0
}

function write_csv_header() {
  local output_file="$1"
  printf 'count,word\n' > "${output_file}"
}

main "${@:-}"
