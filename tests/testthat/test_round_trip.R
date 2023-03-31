test_that("array data survives a round trip unchanged", {
    x <- rnorm(n=64) |> array(c(2, 4, 8))
    conn <- duckdb::duckdb() |> DBI::dbConnect()
    delayed <- store_sql_array(x, dest = conn, name = "foo")
    final <- as(delayed, "array")

    expect_identical(x, final)

    # Edge case with reverse order indices
    expect_identical(
        x[3:1, 3:1],
        final[3:1, 3:1]
    )
})
