#' @export
setClass(
  "SqlArraySeed",
  contains="Array",
  slots=c(
    table="tbl_lazy",
    index_cols="character",
    value_col="character",
    dim="integer"
  )
)

# Allows creating an `SqlArray` using `DelayedArray(SqlArraySeed(...))`
#' @importFrom DelayedArray new_DelayedArray DelayedArray
setMethod(
    "DelayedArray",
    "SqlArraySeed",
    function(seed) DelayedArray::new_DelayedArray(seed, Class="SqlArray")
)

#' Validate a `SqlArraySeed`
#' @noRd
setValidity("SqlArraySeed", function(object){
    checks <- c(
        if(length(object@index_cols) == 0) "At least one index column must be specified!" else character(),
        if(length(object@value_col) != 1) "Exactly one value column must be specified!" else character()
    )

    if (length(checks) == 0)
        TRUE
    else
        checks
})

#' Create a new array seed backed by an SQL table
#' @param tbl An SQL-backed data frame, probably created using
#'  [dbplyr::tbl.src_dbi()]. The table that you use must store each "cell" of
#'  the array in a different row of the table, with different columns indicating
#'  the indices and value of that cell. 0 values do not need to be represented
#'  in the table (ie sparse representation is supported), although they can be
#'  present if you want.
#' @param index_cols A character vector of the columns in `tbl` that indicate
#'  the indices within the array. For example `index_cols=c("a", "b")` means
#'  that `tbl` has at least the columns `a` and `b`, where `a` contains the row
#'  indices of each array entry, and `b` contains the column indices of the
#'  entries. You will need to use a longer vector to support higher dimensional
#'  arrays. Note that all of these columns *must* be integer type columns.
#' @param value_col A character scalar containing the name of the column where
#'  the actual array values can be found. The column type must be some type
#'  compatible with R vectors, such as boolean, string, integer or float.
#' @export
SqlArraySeed <- function(
    tbl,
    index_cols=c("i", "j"),
    value_col="x"
) {
    # This allows S3 connection classes that we don't know about beforehand to
    # be used as inputs. We store in the global env because packages can't
    # be edited at runtime
    if (!(tbl |> class() |> head(1) |> isClass())){
        tbl |> class() |> setOldClass(where=globalenv())
    }
    new(
        "SqlArraySeed",
        table=tbl,
        index_cols = index_cols,
        value_col = value_col,
        dim = calculate_dims(index_cols, tbl)
    )
}

#' Creates a copy of the provided seed, but with the data copied to DuckDB
#' instead of living in its original form.
#'
#' This may significantly increase performance
#' @noRd
copy_local <- function(seed, table_name = stringi::stri_rand_strings(n=1, length=20, pattern="[A-Za-z]")){
    new_tbl <- dplyr::copy_to(
        dest = dbplyr::remote_con(seed@table),
        df = seed@table,
        name = table_name
    )
}

#' Returns a named integer vector that describes the length of each dimension
#' @inheritParams SqlArraySeed
calculate_dims <- function(index_cols, tbl){
    ret <- dplyr::summarise(
        tbl,
        dplyr::across(dplyr::all_of(index_cols), ~max(., na.rm=TRUE)),
    ) |>
        dplyr::collect() |>
        unlist()

    # This
    storage.mode(ret) <- "integer"
    ret
}

# dimnames are not currently supported
setMethod("dimnames", signature = c(x = "SqlArraySeed"), function(x){
    NULL
})

#' @importFrom DelayedArray extract_array
setMethod("extract_array", signature = c(x = "SqlArraySeed"), function(x, index){
    table_name <- stringi::stri_rand_strings(n=1, pattern="[A-Za-z]", length=20)
    conn <- dbplyr::remote_con(x@table)
    expanded_indices <- dplyr::if_else(
        purrr::map_lgl(index, is.null),
        purrr::map(x@dim, seq_len),
        index
    ) |>
        purrr::set_names(names(x@dim))

    # Build a big SQL query that gives us the array values in the range the user
    # has requested, plus the indices at which those values should live in the
    # output array (which aren't the same as the user-provided indices)
    entries <- expanded_indices |>
        purrr::imap(function(index, name){
            tibble::tibble(
                "{name}" := index,
                "pos_{name}" := seq_along(index)
            )
        }) |>
        purrr::set_names(NULL) |>
        do.call(tidyr::expand_grid, args=_) |>
        dplyr::copy_to(conn, df=_, name=table_name, temporary=TRUE) |>
        dplyr::inner_join(x@table, by = names(x@dim)) |>
        dplyr::select(
            dplyr::starts_with("pos"),
            dplyr::any_of(x@value_col)
        ) |>
        dplyr::rename_with(
            .cols=dplyr::starts_with("pos"),
            .fn=~stringr::str_remove(., "pos_")
        ) |>
        dplyr::collect()

    value_col_name <- rlang::sym(x@value_col)

    dim_cols <- entries |>
        dplyr::select(!{{value_col_name}}) |>
        as.matrix()

    value_col <- entries |>
        dplyr::pull({{value_col_name}})

    output <- array(0, dim=expanded_indices |> lengths() |> unname())
    output[dim_cols] <- value_col
    output
})
