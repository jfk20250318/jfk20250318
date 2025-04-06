#!/usr/bin/env bash
# bates_merger.sh
# Watermark and merge PDFs with tree merge strategy.
# Optimizes final output to deduplicate fonts and reduce size.
# Usage: ./bates_merger.sh <input_folder> <output_file.pdf>

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

readonly BATCH_SIZE=100
readonly LOG_FILE="/tmp/bates_merger.log"
exec 5>>"${LOG_FILE}"

function main() {
  validate_args "${@}"
  local -r input_dir="${1}"
  local -r output_pdf="${2}"

  local work_dir
  work_dir="$(mktemp -d)"
  local -r stamped_list_file="${work_dir}/stamped_files.txt"

  log '🔍 Scanning for PDF files in: %s' "${input_dir}"
  find "${input_dir}" -type f -name '*.pdf' | sort | while IFS= read -r input_pdf; do
    function_stamp_and_merge_single_pdf "${input_pdf}" "${work_dir}" "${stamped_list_file}"
  done

  log '📦 Merging all stamped PDFs...'
  local -r merged_pdf="${work_dir}/merged.pdf"
  function_merge_all_files_tree "${stamped_list_file}" "${merged_pdf}"

  log '🧼 Optimizing final merged PDF to deduplicate fonts...'
  function_optimize_pdf "${merged_pdf}" "${output_pdf}"

  log '✅ Done: %s' "${output_pdf}"
  rm -rf "${work_dir}"
}

function validate_args() {
  if [[ "${#@}" -ne 2 || ! -d "${1}" || -z "${2}" ]]; then
    printf 'Usage: %s <input_folder> <output_file.pdf>\n' "${0}" >&2
    exit 1
  fi
}

function log() {
  local -r format="${1}"; shift
  printf "${format}\n" "${@:-}" | tee -a /dev/fd/5
}

function function_stamp_and_merge_single_pdf() {
  local -r input_pdf="${1}"
  local -r work_dir="${2}"
  local -r list_file="${3}"

  local basename
  basename="$(basename "${input_pdf}")"
  local -r filename="${basename%.*}"
  local -r temp_dir="${work_dir}/${filename}"
  mkdir -p "${temp_dir}"

  log '🖋️  Watermarking: %s' "${basename}"
  function_split_and_stamp_pages "${input_pdf}" "${basename}" "${temp_dir}"

  local stamped_pages
  stamped_pages=("${temp_dir}"/stamped-*.pdf)
  local final_pdf
  final_pdf="$(function_tree_merge_pdfs "${stamped_pages[@]}")"
  local -r output_pdf="${work_dir}/stamped_${basename}"

  mv "${final_pdf}" "${output_pdf}"
  printf '%s\n' "${output_pdf}" >> "${list_file}"
  rm -rf "${temp_dir}"

  if [[ "$(wc -l < "${list_file}")" -eq 1 ]]; then
    log '👁️  Previewing first stamped file: %s' "${output_pdf}"
    open "${output_pdf}"
  fi
}

function function_split_and_stamp_pages() {
  local -r input_pdf="${1}"
  local -r basename="${2}"
  local -r temp_dir="${3}"

  qpdf --split-pages "${input_pdf}" "${temp_dir}/page-%05d.pdf"

  local page_num=1
  for page_pdf in "${temp_dir}"/page-*.pdf; do
    local stamp_text="${basename} - Page ${page_num}"
    function_stamp_single_page "${page_pdf}" "${stamp_text}" "${temp_dir}"
    page_num=$((page_num + 1))
  done
}

function function_stamp_single_page() {
  local -r page_pdf="${1}"
  local -r stamp_text="${2}"
  local -r temp_dir="${3}"

  local -r wm_pdf="${temp_dir}/wm-${RANDOM}.pdf"
  local -r stamped_pdf="${temp_dir}/stamped-$(basename "${page_pdf}")"

  gs -q -o "${wm_pdf}" \
    -sDEVICE=pdfwrite \
    -dDEVICEWIDTHPOINTS=612 \
    -dDEVICEHEIGHTPOINTS=792 \
    -dAutoRotatePages=/None \
    -c "
      << /PageSize [612 792] >> setpagedevice
      initmatrix
      gsave
        594 774 translate
        270 rotate
        /Helvetica-Bold findfont 9 scalefont setfont
        1 0 0 setrgbcolor
        0 0 moveto
        (${stamp_text}) show
      grestore
      showpage"

  qpdf --overlay "${wm_pdf}" --repeat=1 -- "${page_pdf}" -- "${stamped_pdf}"

  rm -f "${wm_pdf}" "${page_pdf}"
}

function function_tree_merge_pdfs() {
  local pdfs=("${@}")
  local level=0

  while [[ "${#pdfs[@]}" -gt 1 ]]; do
    level=$((level + 1))
    pdfs=( $(function_merge_pdf_batch "${level}" "${pdfs[@]}") )
  done

  printf '%s\n' "${pdfs[0]}"
}

function function_merge_pdf_batch() {
  local -r level="${1}"; shift
  local batch=("${@}")
  local merged=()

  while [[ "${#batch[@]}" -gt 0 ]]; do
    local subset=("${batch[@]:0:${BATCH_SIZE}}")
    batch=("${batch[@]:${BATCH_SIZE}}")

    local temp_base
    temp_base="$(mktemp "${TMPDIR:-/tmp}/merged-l${level}-XXXXXX")"
    local merged_pdf="${temp_base}.pdf"

    qpdf --empty --pages "${subset[@]}" -- "${merged_pdf}"
    merged+=("${merged_pdf}")
    rm -f "${subset[@]}"
  done

  printf '%s\n' "${merged[@]}"
}

function function_merge_all_files_tree() {
  local -r list_file="${1}"
  local -r output_pdf="${2}"
  local all_files=()

  while IFS= read -r line || [[ -n "${line}" ]]; do
    all_files+=("${line}")
  done < "${list_file}"

  local final_pdf
  final_pdf="$(function_tree_merge_pdfs "${all_files[@]}")"
  mv "${final_pdf}" "${output_pdf}"
}

function function_optimize_pdf() {
  local -r input_pdf="${1}"
  local -r output_pdf="${2}"
  local -r optimized_tmp="${output_pdf}.tmp"

  gs -q -dNOPAUSE -dBATCH \
    -sDEVICE=pdfwrite \
    -dPDFSETTINGS=/prepress \
    -dEmbedAllFonts=true \
    -dSubsetFonts=true \
    -dCompressFonts=true \
    -dDetectDuplicateImages=true \
    -dAutoRotatePages=/None \
    -sOutputFile="${optimized_tmp}" \
    "${input_pdf}"

  mv "${optimized_tmp}" "${output_pdf}"
}

main "${@:-}"
