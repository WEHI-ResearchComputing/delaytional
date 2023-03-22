#' @export
setClass(
  "DuckArraySeed",
  contains="Array",
  slots=c(
    filepath="character",
    index_cols="character",
    value_col="character",
    connection="duckdb_connection",
    duckdb_config="list"
  )
)

#' Validate a `DuckArraySeed`
#' @export
setValidity("DuckArraySeed", function(object){
    checks <- c(
        if(length(object@index_cols) == 0) "At least one index column must be specified!" else NA_character_,
        if(length(object@value_col) != 1) "Exactly one value column must be specified!" else NA_character_,
        if(attr(object@connection, "pid") != Sys.getpid()) "The"
    ) |> na.omit()

    if (length(checks) == 0)
        TRUE
    else
        checks
})

#' Create a new array seed backed by a file DuckDB can read
#' @export
DuckArraySeed <- function(filepath, index_cols=c("i", "j"), value_col="x", duckdb_config=list()){
    # Warning-level validations
    # Error-level validations are located in the formal validator
    if (!file.exists(filepath)){
        paste0('filepath argument: "', filepath, '" does not exist!') |> warning()
    }
    if (!tools::file_ext(filepath) %in% c("parquet", "json", "csv")){
        paste0(
            'filepath argument: "',
            filepath,
            '" has neither a parquet, json nor CSV file extension.'
        ) |> warning()
    }
    new(
        "DuckArraySeed",
        filepath = filepath,
        index_cols = index_cols,
        value_col = value_col,
        connection = connect(duckdb_config),
        duckdb_config = duckdb_config
    )
}

setMethod("dim", signature = c(x = "DuckArraySeed"), function(x){
    res = x@index_cols |>
        DBI::dbQuoteIdentifier(x@connection, x=_) |>
        purrr::map(function(id){
            DBI::sqlInterpolate(x@connection, "MAX(?)", id)
        }) |>
        paste(collapse=", ") |>
        DBI::SQL() |>
        DBI::sqlInterpolate(
            x@connection,
            "SELECT ?cols FROM ?table",
            cols=_,
            table=x@filepath
        ) |>
        DBI::dbGetQuery(x@connection, statement=_)
})

#' Starts a new duckdb connection for use in a `DuckArraySeed`
#' @keywords internal
connect <- function(duckdb_config){
    # We give the connection a PID attribute so that we can identify if the
    # process forks and renders the connection unusable
    do.call(duckdb::duckdb, duckdb_config) |>
        DBI::dbConnect() |>
        structure(pid=Sys.getpid())
}

#' Checks if a given `DuckArraySeed` needs to open a new connection, e.g.
#' because the process has forked since it was created
check_reconnect <- function(seed){
    if(attr(seed@connection, "pid") != Sys.getpid()){
        seed@connection <- connect(seed@duckdb_config)
    }
}
