#!/usr/bin/env bash
# count_pdf_pages.sh
# Count total pages across all PDFs in a specified directory, with fallback and robust error handling.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset
set -o errexit
set -o pipefail

#-------------------------------------------------------------------------------

main() {
  validate_args "${@:-}"
  local -r target_dir="${1}"

  local -r log_dir="./logs"
  local -r log_file="${log_dir}/count_pdf_pages.log"
  mkdir -p "${log_dir}"

  # Open FD 5 as a tee to BOTH the screen and log file
  exec 5> >(tee -a "${log_file}")

  enter_target_dir "${target_dir}"
  find_pdf_files
  count_pdf_pages_for_files
  summarize_results

  popd >/dev/null
  log "🏁 Finished processing '${target_dir}'"
}

#-------------------------------------------------------------------------------

enter_target_dir() {
  local -r dir="${1}"
  log "🚀 Starting PDF page count in: '${dir}'"
  pushd "${dir}" >/dev/null
}

#-------------------------------------------------------------------------------

find_pdf_files() {
  pdf_files=()
  local file
  for file in ./*.pdf; do
    if [[ -f "${file}" ]]; then
      pdf_files+=("${file}")
    fi
  done

  pdf_file_count="${#pdf_files[@]}"
  if [[ "${pdf_file_count}" -eq 0 ]]; then
    log "⚠️ No PDF files found"
    exit 0
  fi

  log "🔎 Found ${pdf_file_count} PDF file(s) to process"
}

#-------------------------------------------------------------------------------

count_pdf_pages_for_files() {
  total_pages=0
  local file_index=0
  local file
  local pages

  for file in "${pdf_files[@]}"; do
    file_index=$((file_index + 1))
    pages=$(get_pdf_page_count "${file}")
    total_pages=$((total_pages + pages))
    log "📄 File ${file_index}/${pdf_file_count}: '${file}' → ${pages} pages"
  done
}

#-------------------------------------------------------------------------------

summarize_results() {
  log "📚 Summary: Processed ${pdf_file_count} file(s)"
  log "🧮 Total pages across all PDFs: ${total_pages}"
}

#-------------------------------------------------------------------------------

validate_args() {
  if [[ "${#}" -ne 1 ]]; then
    printf '❌ Usage: count_pdf_pages.sh <target_directory>\n' >&2
    exit 1
  fi

  local dir="${1}"
  if [[ ! -d "${dir}" ]]; then
    printf "❌ '${dir}' is not a directory\n" >&2
    exit 1
  fi

  if ! command -v pdfinfo >/dev/null; then
    printf '❌ Missing required tool: pdfinfo\n' >&2
    exit 1
  fi
}

#-------------------------------------------------------------------------------

get_pdf_page_count() {
  local file="${1}"
  local pages

  if grep -q '^version https://git-lfs.github.com/spec' "${file}"; then
    log "⚠️ File '${file}' is an unresolved Git LFS pointer — skipping"
    printf '%s\n' 0
    return
  fi

  if pages=$(pdfinfo "${file}" 2>/dev/null | awk '/^Pages:/ {print $2}'); then
    if [[ -n "${pages}" && "${pages}" =~ ^[0-9]+$ ]]; then
      printf '%s\n' "${pages}"
      return
    fi
  fi

  if command -v mdls >/dev/null; then
    pages=$(mdls -name kMDItemNumberOfPages -raw "${file}" 2>/dev/null || true)
    if [[ -n "${pages}" && "${pages}" =~ ^[0-9]+$ ]]; then
      printf '%s\n' "${pages}"
      return
    fi
  fi

  log "⚠️ Could not determine page count for '${file}', assuming 0"
  printf '%s\n' 0
}

#-------------------------------------------------------------------------------

log() {
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  printf '[%s] %s\n' "${timestamp}" "${*}" >&5
}

#-------------------------------------------------------------------------------

# Globals
declare -a pdf_files
declare pdf_file_count=0
declare total_pages=0

main "${@:-}"
