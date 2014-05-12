# `groonga-query-log-run-regression-test`

`groonga-query-log-run-regression-test` is a regression test tool for
Groonga. It is useful when you upgrade Groonga. You can compare search
results by old Groonga and new Groonga by
`groonga-query-log-run-regression-test`. Test queries are read from
query logs. You can use query logs on production environment as is.

## Flow

Here is a work flow to run regression test with
`groonga-query-log-run-regression-test`:

  1. Prepare schema.
  2. Prepare data.
  3. Prepare query logs.
  4. Load schema into both old Groonga and new Groonga.
  5. Load data into both old Groonga and new Groonga.
  6. Send a request extracted from a query log to both old Groonga and
     new Groonga.
  7. Compare responses from old Groonga and new Groonga.
  8. Repeat 6. and 7. for all request in query logs.

If there is any regression, you can find it by the 7. step.

## Usage

This section describe how to use
`groonga-query-log-run-regression-test`.

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

You can put multiple log files like the following:

    query-logs/
    |-- query-20140506.log
    |-- query-20140507.log
    `-- query-20140508.log

Here are links to documents that describe how to create a query log:

  * Groonga server users: You can create a query log file by using
    `--query-log-path` option. See [groonga command][] documentation
    for details.
  * Groonga HTTPD users: You can create a query log file by using
    `groonga_query_log_path` directive. See [groonga_query_log_path][] documentation
    for details.

### Run

Now, you can run regression test.

Let the followings:

  * Use `~/groonga/test` as the working directory to run
    regression test.
  * There is the current Groonga database at `/var/lib/groonga/db`.
  * There are the current query logs at `/var/log/groonga/query-*.log`.
  * The current Groonga is installed at `/opt/groonga-current/bin/groonga`.
  * The new Groonga is installed at `/opt/groonga-new/bin/groonga`.

Install required packages:

    % gem install rroonga groonga-query-log

Prepare the working directory:

    % mkdir -p ~/groonga/test/{schema,indexes,data,query-logs}
    % cd ~/groonga/test/

Extract needed data from the current database:

    % grndump --no-dump-indexes --no-dump-tables /var/lib/groonga/db > schema/ddl.grn
    % grndump --no-dump-schema --no-dump-tables /var/lib/groonga/db > indexes/indexes.grn
    % grndump --no-dump-schema --no-dump-indexes /var/lib/groonga/db > data/data.grn
    % cp /var/log/groonga/query-*.log query-logs/

Run regression test:

    % groonga-query-log-run-regression-test \
        --old-groonga=/opt/groonga-current/bin/groonga \
        --new-groonga=/opt/groonga-new/bin/groonga

It creates new two databases from input data. One is created by the
current Groonga. Another is created by the new Groonga.

It starts to send requests in a query log to both Groonga servers
after databases are created. If responses don't have difference, the
request isn't a problem. If responses have any difference, the request
may be a problem.

You can find details about requests that generate different response in test
result logs. You can find test result logs under `results/`
directory. Test result log file name is the same as input query log
file name. If query log file is `query-logs/query-20140508.log`, test
result log file is `results/query-20140508.log`.

## Advanced usage

There are some advanced usages. This section describes about them.

### `--n-clients`

If your machine has free resource, you can speed up a regression test.

Use `--n-clients` option to send multiple requests concurrently. It
will reduce execution time.

Here is a sample command line to use `--n-clients`:

    % groonga-query-log-run-regression-test \
        --n-clients=4 \
        --old-groonga=/opt/groonga-current/bin/groonga \
        --new-groonga=/opt/groonga-new/bin/groonga

## Conclusion

You can run regression test with
`groonga-query-log-run-regression-test`. It helps you to upgrade
Groonga safely by confirming a new Groonga doesn't have problem with
your data.

  [online index construction]: http://groonga.org/docs/reference/indexing.html#online-index-construction
  [offline index construction]: http://groonga.org/docs/reference/indexing.html#offline-index-construction
  [groonga command]: http://groonga.org/docs/reference/executables/groonga.html
  [groonga_query_log_path]: http://groonga.org/docs/reference/executables/groonga-httpd.html#groonga-query-log-path
