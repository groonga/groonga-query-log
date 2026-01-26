# `groonga-query-log-check-crash`

`groonga-query-log-check-crash` is a tool that supports recovery when Groonga crashes.

If Groonga crashes while updating a database, the database may become corrupted.
It shows tables, columns, and indexes that require recovery, so you can use it when checking what needs to be recovered.

## Usage

This section describes how to use `groonga-query-log-check-crash`.

You need both the process log and the query log to run `groonga-query-log-check-crash`.
For log output settings and content, see the Groonga documentation: https://groonga.org/docs/reference/log.html

Specify the process log and query log. There is no fixed order for specifying them, so specify all logs.

Command example:

```bash
groonga-query-log-check-crash \
  path/to/process-log-2025-* \
  path/to/query-log-2025-* \
  path/to/process-log-2026-* \
  path/to/query-log-2026-*
```

### Options

#### `--command-format`

This script displays any Groonga commands that terminated abnormally.
Specify the format of that command.

You can specify `command` or `uri`, and output will be as follows.

`--command-format=command`:

```
===
[unflushed] 2000-01-01T00:00:01+09:00: 
load \
  --table "Data"
===
```

`--command-format=uri`:

```
===
[unflushed] 2000-01-01T00:00:01+09:00: /d/load?table=Data
===
```

The default is `command`.
When using it as HTTP server, specifying `uri` makes it easier to use when re-running.

#### `--pretty-print`

This is only available when `command` is specified in `--command-format`.

By default, `--pretty-print` is enabled. Disabling it will output Groonga commands on a single line.

`--no-pretty-print`:

```
[unflushed] 2000-01-01T00:00:01+09:00: load --table "Data"
```

#### `--output-level`

You can specify `info` or `debug`. The default value is `info`.
Please use `info` as the default. `debug` provides more detailed output for developers.

## Reading the Output

### Summary

The `Summary` includes the following items.

* `crashed`
  * In the case of `yes`, Groonga has crashed.
  * Please report it with the logs.
* `unflushed`
  * In the case of `yes`, data in memory (non-persistent data) may not have been written to disk (persistent data).
  * Please re-run the target command.
* `unfinished`
  * In the case of `yes`, the target table, column, or index may be broken.
  * Please rebuild the target table, column, or index.
* `leak`
  * In the case of `yes`, Groonga is leaking memory.
  * Please report it with the logs.

Example:

```
Summary:
crashed:yes, unflushed:yes, unfinished:no, leak:no
```

### Unflushed

If the target command exists, the following output is displayed.

```
!!!
!!! [unflushed] Recovery information
!!!
There may be commands that were not flushed between 2000-01-01T00:00:00+09:00 and 2000-01-01T12:00:00+09:00.
These commands may not have been written to the database files, so please re-run them.
===
[unflushed] 2000-01-01T00:00:01+09:00: load --table "Data"
===

Summary:
crashed:yes, unflushed:yes, unfinished:no, leak:no
NG: Please check the display and logs.
```

Lines beginning with `[unflushed]` are commands that may not have been flushed.
Since it may not have been flushed, please re-run that command.

### Unfinished

If the target command exists, the following output is displayed.

```
!!!
!!! [unfinished] Recovery information
!!!
Unfinished commands were found due to abnormal termination or other issues.
It is safer to rebuild the target tables, columns, and indexes because the data may be corrupted.
===
[unfinished] 2000-01-01T00:00:01+09:00: load --table "Data"
===

Summary:
crashed:yes, unflushed:no, unfinished:yes, leak:no
NG: Please check the display and logs.
```

Lines beginning with `[unfinished]` are commands that did not complete normally due to abnormal termination or other issues.
In this case, `Data` and any dependent columns or indexes may be broken and need to be rebuilt.

### Others

If any output other than `unflushed` or `unfinished` was displayed, there might have been an issue with Groonga.
Please report the problem to the Groonga team using the links below, and include the logs used for the check if possible.

* [Groonga issues](https://github.com/groonga/groonga/issues)
* [Groonga discussions](https://github.com/groonga/groonga/discussions)

This will help with investigating the issue.
