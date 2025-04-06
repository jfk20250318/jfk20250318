#!/usr/bin/env bash
# download_updates.sh
# Downloads new JFK NARA archive PDFs not previously downloaded, into a new date-time directory, and logs SHA256 hashes.
# Use --dry-run to preview download plan without executing.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

function main() {
  exec 5>&1
  trap cleanup EXIT INT TERM

  validate_arguments "${@:-}"

  dry_run='false'
  temp_index_file=''
  local folder_arg
  folder_arg=$(extract_folder_arg "${@}")

  if [[ "${1:-}" == '--dry-run' || "${2:-}" == '--dry-run' ]]; then
    dry_run='true'
    log '🧪 Dry run mode enabled.'
  fi

  local -r base_url='https://www.archives.gov'
  local target_dir
  target_dir=$(prepare_target_directory "${folder_arg}" "${dry_run}")
  temp_index_file=$(fetch_index_page "${base_url}/research/jfk/release-2025")

  local all_links_file
  all_links_file=$(mktemp -t jfk_links)
  parse_download_links "${temp_index_file}" > "${all_links_file}"

  local existing_files_file
  existing_files_file=$(mktemp -t jfk_existing)
  find_existing_files > "${existing_files_file}"

  local lfs_files_file
  lfs_files_file=$(mktemp -t jfk_lfs)
  extract_lfs_filenames > "${lfs_files_file}"

  local filtered_links_file
  filtered_links_file=$(mktemp -t jfk_filtered)
  filter_new_files "${all_links_file}" "${existing_files_file}" "${lfs_files_file}" > "${filtered_links_file}"

  report_download_plan "${all_links_file}" "${filtered_links_file}"

  if [[ "${dry_run}" == 'true' ]]; then
    log "📝 Dry run: Retaining index HTML at: ${temp_index_file}"
    return 0
  fi

  download_files "${filtered_links_file}" "${target_dir}"
  sha256sum_new_pdfs "${target_dir}"
  log '✅ Done: All operations completed successfully.'
}

function validate_arguments() {
  if [[ "${#@}" -lt 1 || "${#@}" -gt 2 ]]; then
    log '❌ Error: One required argument (datetime folder name), optional second "--dry-run".'
    exit 1
  fi

  local folder
  folder=$(extract_folder_arg "${@}")
  if [[ -z "${folder}" ]]; then
    log '❌ Error: Folder name must be non-empty.'
    exit 1
  fi
}

function extract_folder_arg() {
  for arg in "${@}"; do
    if [[ "${arg}" != '--dry-run' ]]; then
      printf '%s' "${arg}"
      return
    fi
  done
}

function prepare_target_directory() {
  local name="${1}"
  local readonly dry="${2}"
  local dir="./pdf/${name}"
  if [[ "${dry}" == 'true' ]]; then
    log "💡 Dry run: target directory would be: ${dir}"
  else
    if [[ -d "${dir}" ]]; then
      log '⚠️ Warning: Target directory already exists.'
    else
      mkdir -p "${dir}"
      log "📂 Created target directory: ${dir}"
    fi
  fi
  printf '%s' "${dir}"
}

function fetch_index_page() {
  local -r url="${1}"
  local tmp_file
  tmp_file=$(mktemp -t jfk_index)
  curl -sSL "${url}" -o "${tmp_file}"
  log "🌐 Downloaded index page: ${url}"
  printf '%s' "${tmp_file}"
}

function parse_download_links() {
  local -r index_file="${1}"
  grep -oE 'href="[^\"]+\.pdf"' "${index_file}" | \
    sed -E 's/href="([^"]+)"/\1/' | \
    grep -E '^/' | sort -u
}

function find_existing_files() {
  find ./pdf -type f -name '*.pdf' | sed -E 's#.*/##' | sort -u
}

function extract_lfs_filenames() {
  if [[ -f .gitattributes ]]; then
    grep 'filter=lfs' .gitattributes | sed -E 's#^\./?##; s#\s+filter=.*##' | sed -E 's#.*/##' | sort -u
  fi
}

function normalize_name() {
  local name="${1}"
  name=$(printf '%s' "${name}" | tr ' ' '-')
  name=$(printf '%s' "${name}" | tr -d '()')
  printf '%s\n' "${name}"
}

function filter_new_files() {
  local -r new_links_file="${1}"
  local -r existing_files_file="${2}"
  local -r lfs_files_file="${3}"

  while IFS= read -r url; do
    local filename raw_normalized
    filename=$(basename "${url}")
    raw_normalized=$(normalize_name "${filename}")
    if grep -q "${raw_normalized}" "${existing_files_file}"; then
      continue
    fi
    if [[ -f "${lfs_files_file}" ]] && grep -q "${raw_normalized}" "${lfs_files_file}"; then
      continue
    fi
    printf '%s\n' "${url}"
  done < "${new_links_file}"
}

function download_files() {
  local -r file="${1}"
  local -r target="${2}"
  local -r base_url="https://www.archives.gov"

  while IFS= read -r path; do
    local encoded_path
    encoded_path=$(urlencode_path_only "${path}")
    local full_url="${base_url}${encoded_path}"
    local filename normalized_filename
    filename=$(basename "${path}")
    normalized_filename=$(normalize_name "${filename}")
    local encoded_filename
    encoded_filename=$(urlencode_path_only "${normalized_filename}")
    curl -sSL "${full_url}" -o "${target}/${encoded_filename}"
    log "⬇️  Downloaded: original='${filename}' normalized='${normalized_filename}'"
  done < "${file}"
}

function urlencode_path_only() {
  local raw="${1}"
  local length=${#raw}
  local i=0
  local out=''
  local c hex

  while [[ "${i}" -lt "${length}" ]]; do
    c=${raw:${i}:1}
    case "${c}" in
      [a-zA-Z0-9.~/_-])
        out="${out}${c}"
        ;;
      *)
        printf -v hex '%%%02X' "'${c}"
        out="${out}${hex}"
        ;;
    esac
    i=$((i + 1))
  done
  printf '%s\n' "${out}"
}

function sha256sum_new_pdfs() {
  local -r dir="${1}"
  pushd "./pdf" > /dev/null
  local outfile="sha256-$(basename "${dir}").txt"
  sha256sum "${dir}"/*.pdf | tee "${outfile}" >&5
  popd > /dev/null
  log "🔐 SHA256 hashes written to: ./pdf/${outfile}"
}

function report_download_plan() {
  local -r all_file="${1}"
  local -r new_file="${2}"
  local total
  local to_download

  total=$(wc -l < "${all_file}")
  to_download=$(wc -l < "${new_file}")
  local excluded=$(( total - to_download ))

  log "📊 Total links found: ${total}"
  log "🚫 Already downloaded (excluded): ${excluded}"
  log "📥 Files to be downloaded: ${to_download}"

  while IFS= read -r url; do
    local filename
    filename=$(basename "${url}")
    printf '  - %s\n' "${filename}" | tee -a ./logs/download_updates.log >&5
  done < "${new_file}"
}

function cleanup() {
  if [[ "${dry_run:-false}" == 'true' ]]; then
    return 0
  fi
  if [[ -n "${temp_index_file:-}" && -f "${temp_index_file}" ]]; then
    rm -f "${temp_index_file}"
    log "🧹 Cleaned up temp file: ${temp_index_file}"
  fi
}

function log() {
  local -r log_file="./logs/download_updates.log"
  mkdir -p "$(dirname "${log_file}")"
  printf '%s\n' "${*}" | tee -a "${log_file}" >&5
}

main "${@:-}"
