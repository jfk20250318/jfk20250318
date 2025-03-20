# jfk20250318
JFK files release from national archives -- forks and pull requests are welcomed.

* The `pdf/20250318` folder includes all 1,123 files from the US National Archives.  2 files were renamed to conform to generic filesystem naming conventions.

* The `pdf/20250318-supplemental` folder includes all 75 files from the US National Archives [supplemental drop].

* `low-res-ocr-jfk2025038.pdf` OCR - low quality - all 31,419 pages from first drop.   Original filenames from the US National Archives are embedded in the text with punctuation removed -- these references can be used to go back to the original image file version.

* `word_histogram.txt` Histogram of all words of 3 characters or more in the 31,419 page OCR

* TODO: highest quality OCR
```
├── LICENSE
├── README.md
├── extracted_text.txt [31,419 page original 1123 files extracted to one text file]
├── low-res-ocr-jfk2025038.pdf [31,419 page OCR original 1123 files]
├── pdf
│   ├── 20250318 [1123 files of original drop, canonical naming]
│   │   └── *.pdf
│   ├── 20250318-supplemental [75 files of supplemental drop]
│   │   └── *.pdf
│   ├── sha256-20250318-supplemental.txt
│   └── sha256-20250318.txt
└── word_histogram.txt [words frequency of occurence in 31,419 page original drop]
```
