# Smoke test for the M0 scaffold. It touches no data, real or synthetic.
test_that("the package namespace loads", {
  expect_true(isNamespaceLoaded("nansenbiomass"))
})
