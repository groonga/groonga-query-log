# `groonga-query-log-run-regression-test`

`groonga-query-log-run-regression-test` is a regression test tool for
Groonga. It is useful when you upgrade Groonga. You can compare search
results by old Groonga and new Groonga by
`groonga-query-log-run-regression-test`. Test queries are read from
query logs. You can use query logs on production environment as is.

## Flow

TODO

## Usage

First, you need to prepare input data. Then you can run regression
test.

### Prepare

This section describes how to prepare to run regression test.

Create a directory that has the following structure:

    .
    |-- schema/
    |-- indexes/
    |-- data/
    `-- query-logs/

The following sections describe how to prepare the directories.

#### `schema/`

Put database schema definitions to `schema/` directory. Each file must
have `.grn` extension such as `ddl.grn`.

You can generate a file to be placed into `schema/` from an existing
Groonga database by `grndump` command:

    % grndump --no-dump-indexes --no-dump-tables /groonga/db > schema/ddl.grn

Note that `grndump` command is provided by Rroonga. You can install
Rroonga by the following command:

    % gem install rroonga

#### `indexes/`

Put index definitions to `indexes/` directory. Each file must have
`.grn` extension such as `indexes.grn`.

You can put index definitions to `schema/` directory. But it is better
that put index definitions to `indexes/` directory rather than
`schema/` directory. Because it is faster.

If you use `indexes/` directory, you can use
[offline index construction][]. Offline index construction is 10 times
faster than [online index construction][].

You can generate a file to be placed into `indexes/` from an existing
Groonga database by `grndump` command:

    % grndump --no-dump-schema --no-dump-tables /groonga/db > indexes/indexes.grn

#### `data/`

Put data to `data/` directory. Each file must have `.grn` extension
such as `data.grn`.

You can generate a file to be placed into `data/` from an existing
Groonga database by `grndump` command:

    % grndump --no-dump-schema --no-dump-indexes /groonga/db > data/data.grn

#### `query-logs/`

Put query logs to `query-logs/` directory. Each file must have `.log`
extension such as `query.log`.

You can multiple log files like the following:

    query-logs/
    |-- query-20140506.log
    |-- query-20140507.log
    `-- query-20140508.log

Here are pointers how to create a query log:

  * Groonga server users: You can create a query log file by using
    `--query-log-path` option. See [groonga command][] documentation
    for details.
  * Groonga HTTPD users: You can create a query log file by using
    `groonga_query_log_path` directive. See [groonga_query_log_path][] documentation
    for details.

### Run

Now, you can run regression test.

TODO


  [online index construction]: http://groonga.org/docs/reference/indexing.html#online-index-construction
  [offline index construction]: http://groonga.org/docs/reference/indexing.html#offline-index-construction
  [groonga command]: http://groonga.org/docs/reference/executables/groonga.html
  [groonga_query_log_path]: http://groonga.org/docs/reference/executables/groonga-httpd.html#groonga-query-log-path
