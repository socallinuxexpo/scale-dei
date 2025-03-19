# Scale Diversity Scripts

[![Lint](https://github.com/socallinuxexpo/scale-dei/actions/workflows/lint.yml/badge.svg)](https://github.com/socallinuxexpo/scale-dei/actions/workflows/lint.yml)

## Scale CFP data

Once logged in, download data from:

[https://www.socallinuxexpo.org/scale/22x/demographics.csv](https://www.socallinuxexpo.org/scale/22x/demographics.csv)

But change `22x` to the desired year.

Then run [diversity_reports.rb](src/diversity_reports.rb) on it and stick it in
the spreadsheet:

```bash
diversity_reports.rb <file>
```

## Attendee Data

The [get_reg_demo_stats.py](src/get_reg_demo_stats.py) can be run on the
reg system to generate two CSVs: `demo_data.csv` and `totals.csv`. You
can then run `diversity_reports` on that too:

```bash
diversity_reports.rb --input-type reg --totals-csv totals.csv demo_data.csv
```
