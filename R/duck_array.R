#' DuckArray
#' @include seed.R
setClass(
    "DuckArray",
     contains="DelayedArray",
     representation(seed="DuckArraySeed")
)

#' Saves an array-like to the database as a table
#' @param array Some array-like object
#' @param ... Arguments that will be forwarded to [dplyr::copy_to()]
#' @inheritDotParams dplyr::copy_to dest name overwrite
#' @export
setGeneric("store_sql_array", function(array, ...){})

setMethod(
    "store_sql_array",
    signature = c(array = "array"),
    function(array, ...){
        ndim <- array |> dim() |> length()
        stopifnot(
            `Arrays with more than 16 dimensions are currently t supported` = ndim < 16
        )
        index_colnames <- letters[9:(9 + ndim - 1)]
        dim(array) |>
            purrr::map(seq_len) |>
            purrr::set_names(index_colnames) |>
            expand.grid() |>
            dplyr::mutate(x = as.vector(array)) |>
            dplyr::copy_to(df = _, ...) |>
            DuckArraySeed(index_cols = index_colnames) |>
            DelayedArray()
    }
)
