setOldClass("tbl_duckdb_connection")

#' @importFrom d function
#' @export
setClass(
  "DuckArraySeed",
  contains="Array",
  slots=c(
    table="tbl_duckdb_connection",
    index_cols="character",
    value_col="character",
    dim="integer"
  )
)

#' @importFrom DelayedArray DelayedArray
setMethod(
    "DelayedArray",
    "DuckArraySeed",
    function(seed) new_DelayedArray(seed, Class="DuckArray")
)

#' Validate a `DuckArraySeed`
#' @noRd
setValidity("DuckArraySeed", function(object){
    checks <- c(
        if(length(object@index_cols) == 0) "At least one index column must be specified!" else NA_character_,
        if(length(object@value_col) != 1) "Exactly one value column must be specified!" else NA_character_
    ) |> na.omit()

    if (length(checks) == 0)
        TRUE
    else
        checks
})

#' Create a new array seed backed by a file DuckDB can read
#' @export
DuckArraySeed <- function(
    tbl,
    index_cols=c("i", "j"),
    value_col="x"
) {
    new(
        "DuckArraySeed",
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
copy_local <- function(seed, table_name = stringi::stri_rand_strings(n=1, length=20, pattern="[A-Za-z]")){
    new_tbl <- dplyr::copy_to(
        dest = dbplyr::remote_con(seed@table),
        df = seed@table,
        name = table_name
    )
}

#' Returns a named integer vector that describes the length of each dimension
#' @noRd
calculate_dims <- function(index_cols, tbl){
    dplyr::summarise(
        tbl,
        dplyr::across(dplyr::all_of(index_cols), ~max(., na.rm=TRUE)),
    ) |>
        dplyr::collect() |>
        unlist()
}

setMethod("dimnames", signature = c(x = "DuckArraySeed"), function(x){
    NULL
})

#' @importFrom DelayedArray extract_array
setMethod("extract_array", signature = c(x = "DuckArraySeed"), function(x, index){
    table_name <- stringi::stri_rand_strings(n=1, pattern="[A-Za-z]", length=20)
    conn <- dbplyr::remote_con(x@table)
    result_dims <- dplyr::if_else(
        purrr::map_lgl(index, is.null),
        x@dim,
        lengths(index)
    ) |>
        purrr::set_names(names(x@dim))

    # Build a big SQL query that gives us the array values in the range the user
    # has requested, plus the indices at which those values should live in the
    # output array (which aren't the same as the user-provided indices)
    entries <- result_dims |>
        purrr::map(seq_len) |>
        expand.grid() |>
        dplyr::copy_to(conn, df=_, name=table_name, temporary=TRUE) |>
        dplyr::mutate(
            dplyr::across(dplyr::everything(), dense_rank, .names="rank_{.col}")
        ) |>
        dplyr::inner_join(x@table, by = names(x@dim)) |>
        dplyr::select(
            dplyr::starts_with("rank"),
            dplyr::any_of(x@value_col)
        ) |>
        dplyr::rename_with(
            .cols=dplyr::starts_with("rank"),
            .fn=~stringr::str_remove(., "rank_")
        ) |>
        dplyr::collect()

    value_col_name <- rlang::sym(x@value_col)

    dim_cols <- entries |>
        dplyr::select(!{{value_col_name}}) |>
        as.matrix()

    value_col <- entries |>
        dplyr::pull({{value_col_name}})

    output <- array(0, dim=unname(result_dims))
    output[dim_cols] <- value_col
    output
})
