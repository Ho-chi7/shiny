
context ("runTests")

test_that("runTests works", {
  calls <- list()
  # Tracks the working directory we were in as of the last call
  wd <- NULL

  # A collection of file names that should throw an error when sourced
  filesToError <- "runner2.R"

  sourceStub <- function(...){
    calls[[length(calls)+1]] <<- list(...)
    wd <<- getwd()

    if(list(...)[[1]] %in% filesToError){
      stop("I was told to throw an error")
    }

    NULL
  }

  loadCalls <- list()
  loadSupportStub <- function(...){
    loadCalls[[length(calls)+1]] <<- list(...)
    NULL
  }

  runTestsSpy <- rewire(runTests, sourceUTF8 = sourceStub, loadSupport=loadSupportStub)

  res <- runTestsSpy(test_path("../test-helpers/app1-standard"), assert = FALSE)

  # Should have seen two calls to each test runner
  expect_length(calls, 2)
  expect_match(calls[[1]][[1]], "runner1\\.R$", perl=TRUE)
  expect_match(calls[[2]][[1]], "runner2\\.R$", perl=TRUE)

  # Check environments
  # Each should be loaded into an isolated env that has a common parent
  env1 <- calls[[1]]$envir
  env2 <- calls[[2]]$envir
  expect_identical(parent.env(env1), parent.env(env2))
  expect_true(!identical(env1, env2))

  # Check working directory
  expect_equal(normalizePath(wd), normalizePath(
    file.path(test_path("../test-helpers/app1-standard"), "tests")))

  # Check the results
  expect_equal(all(res$pass), FALSE)
  expect_length(res$file, 2)
  expect_equal(basename(res$file[1]), "runner1.R")
  expect_equal(res[2,]$result[[1]]$message, "I was told to throw an error")
  expect_s3_class(res, "shiny_runtests")

  # Check that supporting files were NOT loaded using Spy Functions
  expect_length(loadCalls, 0)

  # Clear out err'ing files and rerun
  filesToError <- character(0)

  calls <- list()
  res <- runTestsSpy(test_path("../test-helpers/app1-standard"))
  expect_equal(all(res$pass), TRUE)
  expect_equal(basename(res$file), c("runner1.R", "runner2.R"))
  expect_length(calls, 2)
  expect_match(calls[[1]][[1]], "runner1\\.R", perl=TRUE)
  expect_match(calls[[2]][[1]], "runner2\\.R", perl=TRUE)

})

test_that("calls out to shinytest when appropriate", {
  is_legacy_shinytest_val <- TRUE
  is_legacy_shinytest_dir_stub <- function(...){
    is_legacy_shinytest_val
  }

  # All are shinytests
  runTestsSpy <- rewire(runTests, is_legacy_shinytest_dir = is_legacy_shinytest_dir_stub)
  expect_error(
    runTestsSpy(test_path("../test-helpers/app1-standard"), assert = FALSE),
    "not supported"
  )

  # Not shinytests
  is_legacy_shinytest_val <- FALSE
  res <- runTestsSpy(test_path("../test-helpers/app1-standard"))
  expect_s3_class(res, "shiny_runtests")
})

test_that("runTests filters", {
  calls <- list()
  sourceStub <- function(...){
    calls[[length(calls)+1]] <<- list(...)
    NULL
  }

  runTestsSpy <- rewire(runTests, sourceUTF8 = sourceStub)

  # No filter should see two tests (global.R is sourced from another function)
  runTestsSpy(test_path("../test-helpers/app1-standard"))
  expect_length(calls, 2)

  # Filter down to one (global.R is sourced from another function)
  calls <- list()
  runTestsSpy(test_path("../test-helpers/app1-standard"), filter="runner1")
  expect_length(calls, 1)

  calls <- list()
  expect_error(runTestsSpy(test_path("../test-helpers/app1-standard"), filter="i don't exist"), "matched the given filter")
})

test_that("runTests handles the absence of tests", {
  expect_error(runTests(test_path("../test-helpers/app2-nested")), "No tests directory found")
  expect_message(res <- runTests(test_path("../test-helpers/app6-empty-tests")), "No test runners found in")
  expect_equal(res$file, character(0))
  expect_equal(res$pass, logical(0))
  expect_equivalent(res$result, list())
  expect_s3_class(res, "shiny_runtests")
})

test_that("runTests runs as expected without rewiring", {
  appDir <- file.path("..", "test-helpers", "app1-standard")
  df <- testthat::expect_output(
    print(runTests(appDir = appDir, assert = FALSE)),
    "Shiny App Test Results\\n\\* Success\\n  - app1-standard/tests/runner1\\.R\\n  - app1-standard/tests/runner2\\.R"
  )

  expect_equivalent(df, data.frame(
    file = file.path(appDir, "tests", c("runner1.R", "runner2.R")),
    pass = c(TRUE, TRUE),
    result = I(list(1, NULL)),
    stringsAsFactors = FALSE
  ))
  expect_s3_class(df, "shiny_runtests")
})


context("shinyAppTemplate + runTests")
test_that("app template works with runTests", {

  testthat::skip_on_cran()
  testthat::skip_if_not_installed("shinytest", "1.3.1.9000")
  testthat::skip_if(!shinytest::dependenciesInstalled(), "shinytest dependencies not installed. Call `shinytest::installDependencies()`")

  # test all combos
  make_combos <- function(...) {
    args <- list(...)
    combo_dt <- do.call(expand.grid, args)
    lapply(apply(combo_dt, 1, unlist), unname)
  }

  combos <- unique(unlist(
    recursive = FALSE,
    list(
      "all",
      # only test cases for shinytest where appropriate, shinytest is "slow"
      make_combos("app", list(NULL, "module"), "shinytest"),
      # expand.grid on all combos
      make_combos("app", list(NULL, "module"), list(NULL, "rdir"), list(NULL, "testthat"))
    )
  ))

  for (combo in combos) {local({
    random_folder <- paste0("shinyAppTemplate-", paste0(combo, collapse = "_"))
    tempTemplateDir <- file.path(tempdir(), random_folder)
    shinyAppTemplate(tempTemplateDir, combo)
    on.exit(unlink(tempTemplateDir, recursive = TRUE), add = TRUE)

    if (any(c("all", "shinytest", "testthat") %in% combo)) {

      # suppress all output messages
      ignore <- capture.output({
        # do not let an error here stop this test
        # string comparisons will be made below
        test_result <- try({
          runTests(tempTemplateDir)
        }, silent = TRUE)
      })

      expected_test_output <- paste0(
        c(
          "Shiny App Test Results",
          "* Success",
          if (any(c("all", "shinytest") %in% combo))
            paste0("  - ", file.path(random_folder, "tests", "shinytest.R")),
          if (any(c("all", "testthat") %in% combo))
            paste0("  - ", file.path(random_folder, "tests", "testthat.R"))
        ),
        collapse = "\n"
      )

      test_output <- paste0(
        capture.output({
          print(test_result)
        }),
        collapse = "\n"
      )

      if (identical(expected_test_output, test_output)) {
        testthat::succeed()
      } else {
        # be very verbose in the error output to help find root cause of failure
        cat("\nrunTests() output:\n", test_output, "\n\n")
        cat("Expected print output:\n", expected_test_output, "\n")
        testthat::fail(paste0("runTests() output for '", random_folder, "' failed. Received:\n", test_output, "\n"))
      }

    } else {
      expect_error(
        runTests(tempTemplateDir)
      )
    }
  })}

})
