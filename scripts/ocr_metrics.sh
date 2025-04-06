#!/usr/bin/env bash
# ocr_metrics.sh
# Analyze OCR quality metrics from a PDF file by extracting text page by page and counting diacritic vs. plain text content.

# bash configuration:
set -o nounset
set -o errexit
set -o pipefail

#-------------------------------------------------------------------------------

function main() {
  validate_args "${@:-}"
  local -r pdf_file="${1}"

  local -r log_dir="./logs"
  local -r log_file="${log_dir}/ocr_metrics.log"
  mkdir -p "${log_dir}"
  exec 5> >(tee -a "${log_file}")

  log "🔍 Starting OCR quality analysis of: '${pdf_file}'"

  local page_count
  page_count=$(get_page_count "${pdf_file}")
  log "📄 PDF has ${page_count} pages"

  extract_text_per_page "${pdf_file}" "${page_count}"
  process_text_metrics "${page_count}"

  rm -rf "${TMPDIR:-/tmp}/ocr_pages.$$"
  log "✅ Analysis complete"
}

#-------------------------------------------------------------------------------

function validate_args() {
  if [[ "${#}" -ne 1 ]]; then
    printf '❌ Usage: ocr_metrics.sh <input.pdf>\n' >&2
    exit 1
  fi

  local -r pdf="${1}"
  if [[ ! -f "${pdf}" ]]; then
    printf "❌ File '${pdf}' not found\n" >&2
    exit 1
  fi

  if ! command -v pdftotext >/dev/null; then
    printf "❌ 'pdftotext' is required\n" >&2
    exit 1
  fi
}

#-------------------------------------------------------------------------------

function get_page_count() {
  local -r file="${1}"
  pdfinfo "${file}" | awk '/^Pages:/ {print $2}'
}

#-------------------------------------------------------------------------------

function extract_text_per_page() {
  local -r file="${1}"
  local -r pages="${2}"
  local -r outdir="${TMPDIR:-/tmp}/ocr_pages.$$"
  mkdir -p "${outdir}"

  local page
  for page in $(seq 1 "${pages}"); do
    pdftotext -f "${page}" -l "${page}" "${file}" "${outdir}/page_${page}.txt"
  done
}

#-------------------------------------------------------------------------------

function process_text_metrics() {
  local -r pages="${1}"
  local -r outdir="${TMPDIR:-/tmp}/ocr_pages.$$"
  local page
  local text
  local diacritic_count
  local alpha_count
  local ratio
  local diacritic_list=()
  local alpha_list=()
  local ratio_list=()

  for page in $(seq 1 "${pages}"); do
    text=$(tr -d '\n' < "${outdir}/page_${page}.txt")
    diacritic_count=$(printf '%s' "${text}" | grep -o '[\x80-\xFF]' | wc -l | awk '{print $1}')
    alpha_count=$(printf '%s' "${text}" | grep -o '[[:alnum:][:punct:]]' | wc -l | awk '{print $1}')
    ratio=0
    if [[ "${alpha_count}" -gt 0 ]]; then
      ratio=$(awk -v d="${diacritic_count}" -v a="${alpha_count}" 'BEGIN {printf "%.6f", d / a}')
    fi
    diacritic_list+=("${diacritic_count}")
    alpha_list+=("${alpha_count}")
    ratio_list+=("${ratio}")
    log "📄 Page ${page}: Diacritic=${diacritic_count} | Alnum+Punct=${alpha_count} | Ratio=${ratio}"
  done

  summarize "Diacritic Count" "${diacritic_list[@]}"
  summarize "Alnum+Punct Count" "${alpha_list[@]}"
  summarize "Diacritic/Alnum Ratio" "${ratio_list[@]}"
}

#-------------------------------------------------------------------------------

function summarize() {
  local -r label="${1}"
  shift
  local values=("${@}")
  local -r count="${#values[@]}"
  local total=0
  local min="${values[0]}"
  local max="${values[0]}"
  local mean stddev

  local i
  for i in "${values[@]}"; do
    total=$(awk -v sum="${total}" -v val="${i}" 'BEGIN {printf "%.6f", sum + val}')
    min=$(awk -v x="${i}" -v y="${min}" 'BEGIN {print (x<y)?x:y}')
    max=$(awk -v x="${i}" -v y="${max}" 'BEGIN {print (x>y)?x:y}')
  done

  mean=$(awk -v sum="${total}" -v n="${count}" 'BEGIN {printf "%.6f", sum / n}')

  local variance=0
  for i in "${values[@]}"; do
    variance=$(awk -v v="${variance}" -v x="${i}" -v m="${mean}" 'BEGIN {printf "%.6f", v + ((x - m)^2)}')
  done
  stddev=$(awk -v v="${variance}" -v n="${count}" 'BEGIN {printf "%.6f", sqrt(v / n)}')

  log "📊 ${label} → Total=${total}, Mean=${mean}, StdDev=${stddev}, Min=${min}, Max=${max}"
}

#-------------------------------------------------------------------------------

function log() {
  printf '%s\n' "${*}" >&5
}

#-------------------------------------------------------------------------------

main "${@:-}"