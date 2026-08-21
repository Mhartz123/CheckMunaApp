# Date-code evaluation set

Photos of real packaging date codes, with hand-typed ground truth, used to
measure the OCR preprocessing pipeline rather than assert that it helps.

Preprocessing without a measured result is not a contribution, so the number
that goes in the thesis is **character error rate per field, pipeline off vs
on**, plus the count of captures the quality gate rejected.

## Layout

One image per sample, plus a single `ground_truth.csv`:

```
eval/date_codes/
  001_nhydramine_dotmatrix.jpg
  002_debossed_carton.jpg
  ...
  ground_truth.csv
```

## ground_truth.csv

```csv
file,manufactured,expiry,batch,notes
001_nhydramine_dotmatrix.jpg,2025-10,2028-10,P009122,dot-matrix inkjet on white carton
```

- `manufactured` / `expiry` — `YYYY-MM` for month-precision codes, `YYYY-MM-DD`
  when a day is printed. Blank if the pack does not print that field.
- `batch` — exactly as printed, including letters the digit normalizer must not
  touch (`B.177T78` keeps its `B` and `T`).
- `notes` — print method and anything unusual: tamper seal over the code,
  overprint off the baseline grid, debossed rather than inked.

## What to collect

Aim for ~20 images weighted toward the cases that currently fail, since those
are the ones the pipeline exists for:

- dot-matrix / continuous-inkjet marking
- debossed or embossed marking with no pigment
- a tamper seal crossing or occluding the code
- overprinted values sitting off the pre-printed label's baseline grid
- ordinary solid print, as a control that the pipeline does not make good
  captures worse

Photograph them through the app's own expiration guide so the framing and
resolution match what the pipeline actually receives in production — a
full-frame phone photo is much larger than the real crop and will flatter the
results.
