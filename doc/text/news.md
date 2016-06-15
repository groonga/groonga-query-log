# News

## 1.2.2: 2016-06-15

### Improvements

  * groonga-query-log-verify-server: Relaxed random score detect condition.

  * groonga-query-log-verify-server: Supported the case that only one
    response has outputs for `--output_columns "-column"`. The
    `-column` outputs are ignored.

## 1.2.1: 2016-05-27

### Fixes

  * groonga-query-log-verify-server: Fixed a bug that responses aren't
    saved as JSON.

## 1.2.0: 2016-05-27

### Improvements

  * groonga-query-log-verify-server: Added `normalize` command to the
    default check target commands.

  * groonga-query-log-verify-server: Added `logical_shard_list`
    command to the default check target commands.

  * groonga-query-log-verify-server: Added `io_flush` command to the
    default check target commands.

  * groonga-query-log-verify-server: Added `object_exist` command to the
    default check target commands.

  * groonga-query-log-analyzer: Added `--target-commands` option.

  * groonga-query-log-analyzer: Added `--target-tables` option.

### Fixes

  * Fixed undefined variable name error.

  * groonga-query-log-analyzer: Fixed console output format

## 1.1.9: 2016-01-22

### Fixes

  * Fixed an error when parsing query log that includes
    `logical_select` and `logical_range_filter`.

## 1.1.8: 2015-09-14

### Improvements

  * groonga-query-log-run-regression-test: Stopped to loading data in
    parallel. It's too high load for large data.

## 1.1.7: 2015-09-04

### Improvements

  * groonga-query-log-run-regression-test: Supported Windows.
  * groonga-query-log-run-regression-test: Supported `logical_select`,
    `logical_range_filter` and `logical_count` as the test target
    commands.

## 1.1.6: 2015-08-19

### Improvements

  * groonga-query-log-run-regression-test: Added `--no-care-order`
    option that doesn't care order of records in response.
  * groonga-query-log-verify-server: Added `--no-care-order`
    option that doesn't care order of records in response.
  * groonga-query-log-verify-server: Added the following commands to
    the default target command names:
    * `logical_count`
    * `logical_range_filter`
    * `logical_select`

## 1.1.5: 2015-08-12

### Improvements

  * groonga-query-log-run-regression-test: Changed to use `--file`
    command line option of `groonga` instead of redirect to specify
    input.

### Fixes

  * groonga-query-log-extract: Fixed a bug that it fails to boot.

## 1.1.4: 2015-06-11

### Improvements

  * groonga-query-log-run-regression-test: Stopped to output query log
    by default. Use `--output-query-log` option to output query log.

## 1.1.3: 2015-05-26

### Improvements

  * groonga-query-log-run-regression-test: Ignored no command request
    such as `/`.

### Fixes

  * groonga-query-log-analyzer: Fixed a bug that `--no-color` option
    is ignored. [Reported by Gurunavi, Inc.]
  * groonga-query-log-analyzer: Fixed a bug that options aren't
    applied when `--stream` is given.

### Thanks

  * Gurunavi, Inc.

## 1.1.2: 2014-11-20

### Fixes

  * groonga-query-log-format-regression-test-logs: Fixed a bug
    that the command doesn't work in normal usage.

## 1.1.1: 2014-11-06

### Improvements

  * groonga-query-log-run-regression-test: Forced to use JSON output
    type because XML output type and TSV output type for select
    command aren't supported yet.

## 1.1.0: 2014-10-31

### Improvements

  * groonga-query-log-run-regression-test: Supported log output on
    loading data.

## 1.0.9: 2014-09-09

### Improvements

  * groonga-query-log-check-command-version-incompatibility: Added.
    It parses commands in passed query logs and reports incompatible
    items in target command version.

## 1.0.8: 2014-07-23

### Improvements

  * groonga-query-log-analyzer: Added "slow" information to query and
    operations.
  * groonga-query-log-analyzer: Added "json-stream" reporter. It outputs
    a statistic as a JSON in one line.

## 1.0.7: 2014-06-23

### Improvements

  * groonga-query-log-show-running-queries: Added a command that shows
    running queries on the specified base time. It will be useful to
    find a query that causes a problem.

## 1.0.6: 2014-06-02

### Improvements

  * groonga-query-log-run-regression-test: Supported `output_columns=*`
    case.
  * groonga-query-log-format-regression-test-logs: Added a command that
    formats logs by groonga-query-log-run-regression-test.

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
