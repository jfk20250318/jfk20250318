function is_clean(w, raw, clean, threshold) {
  raw = length(w)
  if (raw <= 2) return 0
  clean = w
  gsub(/[^A-Za-z0-9]/, "", clean)
  threshold = raw - int(raw / 10)
  return (length(clean) >= threshold)
}

BEGIN {
  FS = "[[:space:]]+"
  word_count = 0
}

{
  for (i = 1; i <= NF; i++) {
    word = tolower($i)
    gsub(/[^[:print:]]/, "", word)
    gsub(/[^[:alnum:][:punct:]]/, "", word)
    if (is_clean(word)) {
      count[word]++
    }
    word_count++
    if (word_count % 1000 == 0) {
      printf("M") > "/dev/fd/5"
    }
  }
}

END {
  if (word_count % 1000 != 0) {
    printf("\n") > "/dev/fd/5"
  }
  for (w in count) {
    print count[w] "," w
  }
}


