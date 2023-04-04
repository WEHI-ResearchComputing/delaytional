
<!-- README.md is generated from README.Rmd. Please edit that file -->

# delaytional

<!-- badges: start -->

[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![CRAN
status](https://www.r-pkg.org/badges/version/delaytional)](https://CRAN.R-project.org/package=delaytional)
<!-- badges: end -->

`delaytional` provides a backend for
[`DelayedArray`](https://bioconductor.org/packages/release/bioc/html/DelayedArray.html)
that stores the array data in an SQL database. The main motivation for
doing this is so that you can use the impressive performance of
[DuckDB](https://duckdb.org/) to store array data in Parquet files and
query them out of memory (without loading the entire dataset into R).
Other possible use cases include:

- Out-of-memory querying of CSV or NDJSON data, via DuckDB
- Using SQLite databases as array stores
- Re-using an existing database server (DBMS) to support matrix data

## Installation

You can install the development version of `delaytional` from
[GitHub](https://github.com/) with:

``` r
# install.packages("remotes")
remotes::install_github("multimeric/DelayedDuck")
```

## Example

Let’s say we’re working with a fairly large matrix:

``` r
in_mem <- rnorm(n = 4E8) |> matrix(ncol = 2E4)
lobstr::obj_size(in_mem)
#> 3.20 GB
```

This isn’t too bad, but you can easily imagine we might be in trouble if
the matrix were 100 times larger.

Let’s convert it into a `delaytional` array and see if we can improve
that. First we need to write the array to parquet using
`array_to_table`:

``` r
table_dest <- tempfile(fileext=".parquet")
in_mem |>
    delaytional::array_to_table() |>
    arrow::write_parquet(table_dest)
```

Next, we can create an array from the parquet file. This is also how you
would create a `DelayedArray` from an existing parquet dataset that you
didn’t make yourself:

``` r
delayed_parquet <- duckdb::duckdb() |>
  DBI::dbConnect() |>
  dplyr::tbl(table_dest) |>
  delaytional::SqlArraySeed() |>
  DelayedArray::DelayedArray()
```

How big is it now?

``` r
lobstr::obj_size(delayed_parquet)
#> 38.14 kB
```

Now let’s pull out some random indices from the two arrays, and compare
the results:

``` r
set.seed(1)
x = sample.int(n = nrow(in_mem), size = 5)
y = sample.int(n = ncol(in_mem), size = 5)
```

``` r
in_mem[x, y]
#>           [,1]       [,2]        [,3]       [,4]       [,5]
#> [1,] 0.6803626  0.4349818 -0.03947515  1.4685971  0.7045081
#> [2,] 0.9860386 -0.4117989 -1.50756762 -0.5342300  0.3771206
#> [3,] 0.5611791  0.2803572  1.62663412  0.5299880  0.2352429
#> [4,] 0.1042131  0.4311165 -0.02138360  0.3875166 -1.1950585
#> [5,] 1.2098872  1.4683411  0.39057934  0.5912920  1.1341808
```

``` r
delayed_parquet[x, y]
#> <5 x 5> matrix of class DelayedMatrix and type "double":
#>             [,1]        [,2]        [,3]        [,4]        [,5]
#> [1,]  0.68036263  0.43498180 -0.03947515  1.46859710  0.70450814
#> [2,]  0.98603861 -0.41179893 -1.50756762 -0.53422998  0.37712064
#> [3,]  0.56117910  0.28035725  1.62663412  0.52998797  0.23524289
#> [4,]  0.10421312  0.43111652 -0.02138360  0.38751662 -1.19505847
#> [5,]  1.20988716  1.46834111  0.39057934  0.59129200  1.13418078
```

``` r
all.equal(
    in_mem[x, y],
    as.array(delayed_parquet[x, y]),
)
#> [1] TRUE
```

The same results! The only difference is that `delayed_parquet` has a
much smaller memory footprint.
