
<!-- README.md is generated from README.Rmd. Please edit that file -->

# delaytional

<!-- badges: start -->

[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![CRAN
status](https://www.r-pkg.org/badges/version/milton.m)](https://CRAN.R-project.org/package=milton.m)
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

You can install the development version of milton.m from
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
#>            [,1]        [,2]       [,3]       [,4]        [,5]
#> [1,]  0.3125337  0.07070962  0.3528215  0.8328879 -0.96939146
#> [2,] -0.8482889  0.79837248 -0.5737645  1.7307531 -0.35298624
#> [3,]  0.8409811 -1.06002792  1.8046927  2.1882729  0.05517123
#> [4,]  0.3084623  0.53754948 -0.7705885  1.8994851 -0.06250755
#> [5,]  1.9877162  0.31886445 -0.4313568 -0.7592566 -0.40875585
```

``` r
delayed_parquet[x, y]
#> <5 x 5> matrix of class DelayedMatrix and type "double":
#>             [,1]        [,2]        [,3]        [,4]        [,5]
#> [1,]  0.31253372  0.07070962  0.35282154  0.83288791 -0.96939146
#> [2,] -0.84828886  0.79837248 -0.57376450  1.73075314 -0.35298624
#> [3,]  0.84098110 -1.06002792  1.80469267  2.18827287  0.05517123
#> [4,]  0.30846232  0.53754948 -0.77058848  1.89948512 -0.06250755
#> [5,]  1.98771615  0.31886445 -0.43135679 -0.75925659 -0.40875585
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
