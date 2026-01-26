# Copyright (C) 2026  Abe Tomoaki <abe@clear-code.com>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

require "groonga-query-log/command/check-crash"

class CheckCrashCommandTest < Test::Unit::TestCase
  include Helper::Command
  include Helper::Path

  def setup
    @command = GroongaQueryLog::Command::CheckCrash.new
  end

  def fixture_path(*components)
    super("check-crash", *components)
  end

  def crash_log_path
    fixture_path("process", "crash.log")
  end

  def run_command(*command_line)
    super(@command, command_line)
  end

  def test_no_target_logs
    output = <<-OUTPUT
Usage: run-test [options] LOG1 ...
        --command-format=FORMAT      Specify the output format of the Groonga command that had a problem. [command]
                                     (command, uri)
        --[no-]pretty-print          Specify to make command output easier to read. [true]
                                     Only available when `--command-format=command` is specified.
        --output-level=LEVEL         Specify the output level. [info]
                                     Specifying 'debug' displays detailed information.
                                     (info, debug)
OUTPUT
    assert_equal([false, output],
                 run_command())
  end

  def test_not_exist_path
    error = assert_raise(Errno::ENOENT) do
      run_command("/path/to/nonexistent")
    end
    assert_equal("No such file or directory @ rb_sysopen - /path/to/nonexistent",
                 error.message)
  end

  class FormatInfoTest < self
    def expected(unflushed_command)
      <<-OUTPUT

!!!
!!! Important entries
!!!
It contained logs that require checking.
If you need help, please feel free to contact the community: https://groonga.org/docs/community.html
===
2000-01-01T12:00:00+09:00: 1: 00000000: critical: -- CRASHED!!! --
2000-01-01T12:00:00+09:00: 1: 00000000: critical: ...trace
2000-01-01T12:00:00+09:00: 1: 00000000: critical: ----------------
===

!!!
!!! [unflushed] Recovery information
!!!
There may be commands that were not flushed between 2000-01-01T00:00:00+09:00 and 2000-01-01T12:00:00+09:00.
These commands may not have been written to the database files, so please re-run them.
===
[unflushed] 2000-01-01T00:00:01+09:00: #{unflushed_command}
===

Summary:
crashed:yes, unflushed:yes, unfinished:no, leak:no
NG: Please check the display and logs.
      OUTPUT
    end

    def test_command_format_pretty_print
      assert_equal([true, expected("\nload \\\n  --table \"Data\"")],
                   run_command("--command-format=command",
                               fixture_path("process", "crash.log"),
                               fixture_path("query", "load", "unflushed", "no-flush.log")))
    end

    def test_command_format_one_line
      assert_equal([true, expected("load --table \"Data\"")],
                   run_command("--command-format=command",
                               "--no-pretty-print",
                               crash_log_path,
                               fixture_path("query", "load", "unflushed", "no-flush.log")))
    end

    def test_uri_format
      assert_equal([true, expected("/d/load?table=Data")],
                   run_command("--command-format=uri",
                               crash_log_path,
                               fixture_path("query", "load", "unflushed", "no-flush.log")))
    end
  end

  class OutputLevelInfoTest < self
    def test_normal
      output = <<-OUTPUT

Summary:
crashed:no, unflushed:no, unfinished:no, leak:no
OK: no problems.
OUTPUT
      assert_equal([true, output],
                   run_command(fixture_path("process", "normal.log"),
                               fixture_path("query", "load", "flushed", "only-opened.log")))
    end

    # todo: add other tests
  end

  class OutputLevelDebugTest < self
    def run_command(*command_line)
      command_line.push("--output-level=debug")
      command_line.push("--command-format=uri")
      super(*command_line)
    end

    def test_normal
      output = <<-OUTPUT
#{[
  :process,
  :success,
  "99.9.9",
  "2000-01-01T00:00:00+09:00",
  "2000-01-01T00:00:10+09:00",
  nil,
  fixture_path("process", "normal.log"),
  fixture_path("process", "normal.log"),
].inspect}

Summary:
crashed:no, unflushed:no, unfinished:no, leak:no
OK: no problems.
      OUTPUT
      assert_equal([true, output],
                   run_command(fixture_path("process", "normal.log"),
                               fixture_path("query", "load", "flushed", "only-opened.log")))
    end

    def test_leak
      output = <<-OUTPUT
#{[
  :process,
  :success,
  "99.9.9",
  "2000-01-01T00:00:00+09:00",
  "2000-01-01T00:00:10+09:00",
  nil,
  fixture_path("process", "leak.log"),
  fixture_path("process", "leak.log"),
].inspect}
#{[
  :leak,
  "99.9.9",
  3,
  "2000-01-01T00:00:10+09:00",
  nil,
  fixture_path("process", "leak.log"),
].inspect}

Summary:
crashed:no, unflushed:no, unfinished:no, leak:yes
NG: Please check the display and logs.
      OUTPUT
      assert_equal([true, output],
                   run_command(fixture_path("process", "leak.log"),
                               fixture_path("query", "load", "flushed", "only-opened.log")))
    end

    sub_test_case("unfinished") do
      def expected(unfinished_command)
        <<-OUTPUT
#{[
  :process,
  :crashed,
  "99.9.9",
  "2000-01-01T00:00:00+09:00",
  "2000-01-01T12:00:00+09:00",
  1,
  fixture_path("process", "crash.log"),
  fixture_path("process", "crash.log"),
].inspect}

!!!
!!! Important entries
!!!
It contained logs that require checking.
If you need help, please feel free to contact the community: https://groonga.org/docs/community.html
===
2000-01-01T12:00:00+09:00: 1: 00000000: critical: -- CRASHED!!! --
2000-01-01T12:00:00+09:00: 1: 00000000: critical: ...trace
2000-01-01T12:00:00+09:00: 1: 00000000: critical: ----------------
===

!!!
!!! [unfinished] Recovery information
!!!
Unfinished commands were found due to abnormal termination or other issues.
It is safer to rebuild the target tables, columns, and indexes because the data may be corrupted.
===
[unfinished] 2000-01-01T00:00:01+09:00: #{unfinished_command}
===

Summary:
crashed:yes, unflushed:no, unfinished:yes, leak:no
NG: Please check the display and logs.
        OUTPUT
      end

      data(
        load: { command: "load", unfinished_command: "/d/load?table=Data" },
        delete: { command: "delete", unfinished_command: "/d/delete?key=2&table=Data" },
        column_create: {
          command: "column_create",
          unfinished_command: "/d/column_create?flags=COLUMN_INDEX%7CWITH_POSITION&name=blog_title&source=title&table=Terms&type=Site",
        },
        select_load: {
          command: "select",
          unfinished_command: "/d/select?load_columns=_key%2Ccount&load_table=Data&load_values=_key%2Ccount&table=Raw",
        },
      )
      def test_unfinished
        assert_equal([true, expected(data[:unfinished_command])],
                     run_command(crash_log_path,
                                 fixture_path("query", data[:command], "unfinished.log")))
      end
    end

    sub_test_case("flushed") do
      def expected
        <<-OUTPUT
#{[
  :process,
  :crashed,
  "99.9.9",
  "2000-01-01T00:00:00+09:00",
  "2000-01-01T12:00:00+09:00",
  1,
  fixture_path("process", "crash.log"),
  fixture_path("process", "crash.log"),
].inspect}

!!!
!!! Important entries
!!!
It contained logs that require checking.
If you need help, please feel free to contact the community: https://groonga.org/docs/community.html
===
2000-01-01T12:00:00+09:00: 1: 00000000: critical: -- CRASHED!!! --
2000-01-01T12:00:00+09:00: 1: 00000000: critical: ...trace
2000-01-01T12:00:00+09:00: 1: 00000000: critical: ----------------
===

Summary:
crashed:yes, unflushed:no, unfinished:no, leak:no
NG: Please check the display and logs.
        OUTPUT
      end

      data(
        # load
        "command:load flush:target-name&recursive=dependent": {
          command: "load",
          flush_case: "target-name-recursive-dependent",
        },
        "command:load flush:only-opened": { command: "load", flush_case: "only-opened" },
        "command:load flush:recursive=yes": { command: "load", flush_case: "recursive-yes" },
        "command:load&columns flush:only-opened": { command: "load", flush_case: "columns-only-opened" },
        "command:load&columns flushtarget-name&recursive=dependent:": {
          command: "load",
          flush_case: "columns-target-name-recursive-dependent",
        },
        # delete
        "command:delete flush:target-name&recursive=dependent": {
          command: "delete",
          flush_case: "target-name-recursive-dependent",
        },
        "command:delete flush:only-opened": { command: "delete", flush_case: "only-opened" },
        "command:delete flush:recursive=yes": { command: "delete", flush_case: "recursive-yes" },
        # truncate
        "command:truncate flush:target-name&recursive=dependent": {
          command: "truncate",
          flush_case: "target-name-recursive-dependent",
        },
        "command:truncate flush:only-opened": { command: "truncate", flush_case: "only-opened" },
        "command:truncate flush:recursive=yes": { command: "truncate", flush_case: "recursive-yes" },
        # table_create
        "command:table_create flush:target-name&recursive=dependent": {
          command: "table_create",
          flush_case: "target-name-recursive-dependent",
        },
        "command:table_create flush:only-opened": { command: "table_create", flush_case: "only-opened" },
        "command:table_create flush:recursive=yes": { command: "table_create", flush_case: "recursive-yes" },
        # column_create
        "command:column_create flush:target-name&recursive=dependent": {
          command: "column_create",
          flush_case: "target-name-recursive-dependent",
        },
        "command:column_create flush:only-opened": { command: "column_create", flush_case: "only-opened" },
        "command:column_create flush:recursive=yes": { command: "column_create", flush_case: "recursive-yes" },
        # select (with load)
        "command:select-load flush:target-name&recursive=dependent": {
          command: "select",
          flush_case: "target-name-recursive-dependent",
        },
        "command:select-load flush:only-opened": { command: "select", flush_case: "only-opened" },
        "command:select-load flush:recursive=yes": { command: "select", flush_case: "recursive-yes" },
      )
      def test_flushed(data)
        assert_equal([true, expected],
                     run_command(crash_log_path,
                                 fixture_path("query", data[:command], "flushed", "#{data[:flush_case]}.log")))
      end
    end

    sub_test_case("unflushed") do
      def expected(unflushed_command)
        <<-OUTPUT
#{[
  :process,
  :crashed,
  "99.9.9",
  "2000-01-01T00:00:00+09:00",
  "2000-01-01T12:00:00+09:00",
  1,
  fixture_path("process", "crash.log"),
  fixture_path("process", "crash.log"),
].inspect}

!!!
!!! Important entries
!!!
It contained logs that require checking.
If you need help, please feel free to contact the community: https://groonga.org/docs/community.html
===
2000-01-01T12:00:00+09:00: 1: 00000000: critical: -- CRASHED!!! --
2000-01-01T12:00:00+09:00: 1: 00000000: critical: ...trace
2000-01-01T12:00:00+09:00: 1: 00000000: critical: ----------------
===

!!!
!!! [unflushed] Recovery information
!!!
There may be commands that were not flushed between 2000-01-01T00:00:00+09:00 and 2000-01-01T12:00:00+09:00.
These commands may not have been written to the database files, so please re-run them.
===
[unflushed] 2000-01-01T00:00:01+09:00: #{unflushed_command}
===

Summary:
crashed:yes, unflushed:yes, unfinished:no, leak:no
NG: Please check the display and logs.
        OUTPUT
      end

      data(
        # load
        "command:load flush:no": {
          command: "load",
          flush_case: "no-flush",
          unflushed_command: "/d/load?table=Data"
        },
        "command:load flush:only-opened": {
          command: "load",
          flush_case: "only-opened",
          unflushed_command: "/d/load?table=Data"
        },
        "command:load flush:recursive=no": {
          command: "load",
          flush_case: "recursive-no",
          unflushed_command: "/d/load?table=Data"
        },
        "command:load flush:target-name&recursive=yes": {
          command: "load",
          flush_case: "target-name-recursive-yes",
          unflushed_command: "/d/load?table=Data"
        },
        "command:load flush:target-name&recursive=no": {
          command: "load",
          flush_case: "target-name-recursive-no",
          unflushed_command: "/d/load?table=Data"
        },
        "command:load&columns flush:only-opened": {
          command: "load",
          flush_case: "columns-only-opened",
          unflushed_command: "/d/load?columns=_key%2Ccount&table=Data"
        },
        "command:load&columns flush:target-name&recursive=dependent": {
          command: "load",
          flush_case: "columns-target-name-recursive-dependent",
          unflushed_command: "/d/load?columns=_key%2Ccount&table=Data"
        },
        # delete
        "command:delete flush:no": {
          command: "delete",
          flush_case: "no-flush",
          unflushed_command: "/d/delete?key=2&table=Data"
        },
        "command:delete flush:only-opened": {
          command: "delete",
          flush_case: "only-opened",
          unflushed_command: "/d/delete?key=2&table=Data"
        },
        "command:delete flush:recursive=no": {
          command: "delete",
          flush_case: "recursive-no",
          unflushed_command: "/d/delete?key=2&table=Data"
        },
        "command:delete flush:target-name&recursive=yes": {
          command: "delete",
          flush_case: "target-name-recursive-yes",
          unflushed_command: "/d/delete?key=2&table=Data"
        },
        "command:delete flush:target-name&recursive=no": {
          command: "delete",
          flush_case: "target-name-recursive-no",
          unflushed_command: "/d/delete?key=2&table=Data"
        },
        # truncate
        "command:truncate flush:no": {
          command: "truncate",
          flush_case: "no-flush",
          unflushed_command: "/d/truncate?target_name=Data"
        },
        "command:truncate flush:only-opened": {
          command: "truncate",
          flush_case: "only-opened",
          unflushed_command: "/d/truncate?target_name=Data"
        },
        "command:truncate flush:recursive=no": {
          command: "truncate",
          flush_case: "recursive-no",
          unflushed_command: "/d/truncate?target_name=Data"
        },
        "command:truncate flush:target-name&recursive=yes": {
          command: "truncate",
          flush_case: "target-name-recursive-yes",
          unflushed_command: "/d/truncate?target_name=Data"
        },
        "command:truncate flush:target-name&recursive=no": {
          command: "truncate",
          flush_case: "target-name-recursive-no",
          unflushed_command: "/d/truncate?target_name=Data"
        },
        # table_create
        "command:table_create flush:no": {
          command: "table_create",
          flush_case: "no-flush",
          unflushed_command: "/d/table_create?flags=TABLE_HASH_KEY&key_type=ShortText&name=Data"
        },
        "command:table_create flush:only-opened": {
          command: "table_create",
          flush_case: "only-opened",
          unflushed_command: "/d/table_create?flags=TABLE_HASH_KEY&key_type=ShortText&name=Data"
        },
        "command:table_create flush:recursive=no": {
          command: "table_create",
          flush_case: "recursive-no",
          unflushed_command: "/d/table_create?flags=TABLE_HASH_KEY&key_type=ShortText&name=Data"
        },
        "command:table_create flush:target-name&recursive=yes": {
          command: "table_create",
          flush_case: "target-name-recursive-yes",
          unflushed_command: "/d/table_create?flags=TABLE_HASH_KEY&key_type=ShortText&name=Data"
        },
        "command:table_create flush:target-name&recursive=no": {
          command: "table_create",
          flush_case: "target-name-recursive-no",
          unflushed_command: "/d/table_create?flags=TABLE_HASH_KEY&key_type=ShortText&name=Data"
        },
        # column_create
        "command:column_create flush:no": {
          command: "column_create",
          flush_case: "no-flush",
          unflushed_command: "/d/column_create?name=count&table=Data&type=Int32"
        },
        "command:column_create flush:only-opened": {
          command: "column_create",
          flush_case: "only-opened",
          unflushed_command: "/d/column_create?name=count&table=Data&type=Int32"
        },
        "command:column_create flush:recursive=no": {
          command: "column_create",
          flush_case: "recursive-no",
          unflushed_command: "/d/column_create?name=count&table=Data&type=Int32"
        },
        "command:column_create flush:target-name&recursive=yes": {
          command: "column_create",
          flush_case: "target-name-recursive-yes",
          unflushed_command: "/d/column_create?name=count&table=Data&type=Int32"
        },
        "command:column_create flush:target-name&recursive=no": {
          command: "column_create",
          flush_case: "target-name-recursive-no",
          unflushed_command: "/d/column_create?name=count&table=Data&type=Int32"
        },
        # select (with load)
        "command:select-load flush:no": {
          command: "select",
          flush_case: "no-flush",
          unflushed_command: "/d/select?load_columns=_key%2Ccount&load_table=Data&load_values=_key%2Ccount&table=Raw",
        },
        "command:select-load flush:only-opened": {
          command: "select",
          flush_case: "only-opened",
          unflushed_command: "/d/select?load_columns=_key%2Ccount&load_table=Data&load_values=_key%2Ccount&table=Raw",
        },
        "command:select-load flush:recursive=no": {
          command: "select",
          flush_case: "recursive-no",
          unflushed_command: "/d/select?load_columns=_key%2Ccount&load_table=Data&load_values=_key%2Ccount&table=Raw",
        },
        "command:select-load flush:target-name&recursive=yes": {
          command: "select",
          flush_case: "target-name-recursive-yes",
          unflushed_command: "/d/select?load_columns=_key%2Ccount&load_table=Data&load_values=_key%2Ccount&table=Raw",
        },
        "command:select-load flush:target-name&recursive=no": {
          command: "select",
          flush_case: "target-name-recursive-no",
          unflushed_command: "/d/select?load_columns=_key%2Ccount&load_table=Data&load_values=_key%2Ccount&table=Raw",
        },
      )
      def test_unflushed(data)
        assert_equal([true, expected(data[:unflushed_command])],
                     run_command(crash_log_path,
                                 fixture_path("query", data[:command], "unflushed", "#{data[:flush_case]}.log")))
      end
    end

    def test_normal_select
      output = <<-OUTPUT
#{[
  :process,
  :crashed,
  "99.9.9",
  "2000-01-01T00:00:00+09:00",
  "2000-01-01T12:00:00+09:00",
  1,
  fixture_path("process", "crash.log"),
  fixture_path("process", "crash.log"),
].inspect}

!!!
!!! Important entries
!!!
It contained logs that require checking.
If you need help, please feel free to contact the community: https://groonga.org/docs/community.html
===
2000-01-01T12:00:00+09:00: 1: 00000000: critical: -- CRASHED!!! --
2000-01-01T12:00:00+09:00: 1: 00000000: critical: ...trace
2000-01-01T12:00:00+09:00: 1: 00000000: critical: ----------------
===

Summary:
crashed:yes, unflushed:no, unfinished:no, leak:no
NG: Please check the display and logs.
      OUTPUT
      assert_equal([true, output],
                   run_command(crash_log_path,
                               fixture_path("query", "select", "unflushed", "no-load.log")))
    end
  end
end
