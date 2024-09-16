# mwp manual

* Uses `mkdocs`
  * Build navigable and searchable HTML documentation
  * Generate PDF manual

## Dependencies

As most people won't want to actually build the manual, these are not hard build requirements, but are necessary to build the manual.

* mkdocs
* mkdocs-with-pdf
* mkdocs-macros-plugin
* mkdocs-material

Most distros don't package all of these; you'll end up with `pip` packages as well.

The HTML site can then be build with `mkdocs build` or `mkdocs serve`.

The PDF is built with `ENABLE_PDF_EXPORT=1 mkdocs build`

The PDF file is extremely large (c. 40MB), reduce to an acceptable size ...

```
gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/ebook \
  -dNOPAUSE -dBATCH -dColorImageResolution=150 \
    -sOutputFile=../mwptools.pdf mwptools.pdf
```

Push HTML docs to GitHub pages (maintainer):

`mkdocs gh-deploy --force`
