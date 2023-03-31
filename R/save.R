#' Converts an array into a "long" format data frame
#'
#' This function is designed to allow you to convert an array first into a data
#' frame, allowing you to then save it using a function such as [arrow::write_parquet()] or
#' [utils::write.csv()]. Then, you can open the resulting file in a compatible
#' database (notably DuckDB), which you can use to construct an [SqlArray()].
#'
#' @param array An R array, with no more than 15 dimensions
#' @return A [tibble::tbl_df-class]
#' @export
#' @examples
#' rnorm(n = 16) |>
#'  matrix(ncol = 4) |>
#'  delaytional::array_to_table()
array_to_table <- function(arr, index_colnames = default_index_colnames(arr)){
    dim(arr) |>
        purrr::map(seq_len) |>
        purrr::set_names(index_colnames) |>
        expand.grid() |>
        dplyr::mutate(x = as.vector(arr))
}

#' Generates some default column names for the index columns
#' @param arr Some native R array
#' @keywords internal
default_index_colnames <- function(arr){
    ndim <- arr |> dim() |> length()
    stopifnot(
        `Arrays with more than 16 dimensions are currently not supported` = ndim < 16
    )
    letters[9:(9 + ndim - 1)]
}

#' Saves an array-like to the database as a table
#' @inheritParams array_to_table
#' @inheritDotParams dplyr::copy_to dest name overwrite
#' @return An [SqlArray-class] instance
#' @export
store_sql_array <- function(
    arr,
    index_colnames = default_index_colnames(arr),
    ...
){
    array_to_table(arr) |>
        dplyr::copy_to(df = _, ...) |>
        SqlArraySeed(index_cols = index_colnames) |>
        DelayedArray()
}
