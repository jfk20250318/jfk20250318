#!/bin/bash

total_pages=0
for file in *.pdf; do
    pages=$(pdfinfo "$file" | awk '/Pages:/ {print $2}')
    total_pages=$((total_pages + pages))
    echo "$file has $pages pages"
done
echo "Total pages $total_pages"

