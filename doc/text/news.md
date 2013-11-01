# News

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
