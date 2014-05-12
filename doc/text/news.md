# News

## 1.0.5: 2014-05-12

### Improvements

  * groonga-query-log-verify-server: Supported `groonga-client` 0.0.8.
  * groonga-query-log-verify-server: Supported comparing errors.
  * groonga-query-log-run-regression-test: Added a command that
    runs regression test. It is based on groonga-query-log-verify-server.

## 1.0.4: 2014-02-09

### Improvements

  * groonga-query-log-verify-server: Supported reading input from the
    standard input.
  * groonga-query-log-verify-server: Supported logging error on
    connecting server.
  * groonga-query-log-verify-server: Supported random sort select.
  * groonga-query-log-verify-server: Added `--abort-on-exception` debug option.

## 1.0.3: 2014-01-06

### Improvements

  * groonga-query-log-verify-server: Added a command that verifies two
    servers returns the same response for the same request.
    (experimental)

### Fixes

  * groonga-query-log-analyzer: Fixed a bug `--stream` doesn't work.

## 1.0.2: 2013-11-01

### Improvements

  * [GitHub#1] Add Travis CI status image to README.
    Patch by Kengo Suzuki. Thanks!!!
  * Dropped Ruby 1.8 support.
  * Added groonga-query-log-replay that replays queries in query log.
  * Added groonga-query-log-detect-memory-leak that detects
    a memory leak by executing each query in query log.

### Thanks

  * Kengo Suzuki

## 1.0.1: 2012-12-21

### Improvements

 * Added "groonga-query-log-extract" command and classes implementing it.
   "groonga-query-log-extract" is the command to extract commands
   (table_create ..., load..., select... and so on) from query
   logs. "groonga-query-log-extract --help" shows its usage.

### Changes

 * Rename groonga-query-log-analyzer to groonga-query-log-analyze
   (removed trailing "r").
 * Raised error and exited of each running command for no specified
   input files, redirects, and pipe via standard input.

## 1.0.0: 2012-12-14

The first release!!!
