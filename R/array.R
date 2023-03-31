#' A DelayedArray backed by an SQL table
#' @export
#' @include seed.R
setClass(
    "SqlArray",
     contains="DelayedArray",
     representation(seed="SqlArraySeed")
)
