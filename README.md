# jfk20250318 thru jfk20250320
JFK files release from national archives -- forks and pull requests are welcomed.

* The `pdf/20250318-1930h` folder includes all 1,123 files from the US National Archives delivered at 1930h.  2 files were renamed to conform to generic filesystem naming conventions.
  * 31,419 pages

* The `pdf/20250318-2230h` folder includes all 1,059 files from the US National Archives delivered at 2230h.  4 files were renamed to conform to generic filesystem naming conventions.

* The `pdf/20250320-2130h` folder includes all 161 files from the US National Archives delivered at 20250320-2130h.
  *  14,318 pages

* The `pdf/20250318-supplemental` folder includes all 75 files from the US National Archives [supplemental drop].
  * 489 pages 

* `low-res-ocr-jfk20250318-1930h.pdf` OCR - low quality - all 31,419 pages from 20250318-1930h.   Original filenames from the US National Archives are embedded in the text with punctuation removed -- these references can be used to go back to the original image file version.

* `med-res-ocr-jfk2025038-supplemental.pdf` OCR - medium quality - all 489 pages from supplemental drop.

* `low-res-ocr-jfk20250320-2130h.pdf` OCR - medium quality - all 14,318 pages from 20250320-2130h.   Original filenames from the US National Archives are embedded in the text with punctuation removed -- these references can be used to go back to the original image file version.

* `20250318-1930h-word-histogram.txt` Histogram of all words of 3 characters or more in the 31,419 page OCR

* TODO: highest quality OCR
```
├── LICENSE
├── README.md
├── 20250318-1930h-extracted-text.txt [31,419 page original 1123 files extracted to one text file]
├── low-res-ocr-jfk20250318-1930h.pdf [31,419 page OCR original 1123 files]
├── med-res-ocr-jfk20250318-supplemental.pdf [489 page OCR original 75 files]
├── med-res-ocr-jfk20250320-2130h.pdf [14,318 page OCR original 161 files]
├── pdf
│   ├── 20250318-1930h [1123 files of original drop, canonical naming]
│   │   └── *.pdf
│   ├── 20250318-2230h [1059 files of original drop, canonical naming]
│   │   └── *.pdf
│   ├── 20250320-2130h [161 files of original drop, canonical naming]
│   │   └── *.pdf
│   ├── 20250318-supplemental [75 files of supplemental drop]
│   │   └── *.pdf
│   ├── sha256-20250318-supplemental.txt
│   ├── sha256-20250318-1930h.txt
│   ├── sha256-20250318-2230h.txt
│   └── sha256-20250320-2130h.txt
└── 20250318-1930h-word-histogram.txt [words frequency of occurence in 31,419 page original drop]
```

TODO: still some incorrect PDF files in the 2230h drop -- will need to investigate.  confirmed that local copy is byte-for-byte the same as the archives.gov version, so corruption is upstream
