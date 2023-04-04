
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
remotes::install_github("WEHI-ResearchComputing/delaytional")
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
#>            [,1]       [,2]       [,3]       [,4]       [,5]
#> [1,] -0.6700517  0.9356821 -1.0847204 -0.3044768  0.3201105
#> [2,]  0.3117883 -1.1637274  0.5206586  0.6136792  0.3863917
#> [3,]  0.5248609 -1.1065383 -0.4499743  1.1963352 -0.8393234
#> [4,] -0.4036493  1.7691156 -1.7958300 -0.7343334  0.2773608
#> [5,] -0.5505380  1.4433347  0.3846686 -1.5767486  2.5452338
```

``` r
delayed_parquet[x, y]
#> <5 x 5> matrix of class DelayedMatrix and type "double":
#>            [,1]       [,2]       [,3]       [,4]       [,5]
#> [1,] -0.6700517  0.9356821 -1.0847204 -0.3044768  0.3201105
#> [2,]  0.3117883 -1.1637274  0.5206586  0.6136792  0.3863917
#> [3,]  0.5248609 -1.1065383 -0.4499743  1.1963352 -0.8393234
#> [4,] -0.4036493  1.7691156 -1.7958300 -0.7343334  0.2773608
#> [5,] -0.5505380  1.4433347  0.3846686 -1.5767486  2.5452338
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
