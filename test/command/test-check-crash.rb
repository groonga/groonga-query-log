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
====

!!!
!!! [unflushed] Recovery information
!!!
There may be commands that were not flushed between 2000-01-01T00:00:00+09:00 and 2000-01-01T12:00:00+09:00.
These commands may not have been written to the database files, so please re-run them.
===
[unflushed] 2000-01-01T00:00:01+09:00: #{unflushed_command}
====

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
====

!!!
!!! [unfinished] Recovery information
!!!
Unfinished commands were found due to abnormal termination or other issues.
It is safer to rebuild the target tables, columns, and indexes because the data may be corrupted.
===
[unfinished] 2000-01-01T00:00:01+09:00: #{unfinished_command}
====

Summary:
crashed:yes, unflushed:no, unfinished:yes, leak:no
NG: Please check the display and logs.
        OUTPUT
      end

      def test_load
        assert_equal([true, expected("/d/load?table=Data")],
                     run_command(crash_log_path,
                                 fixture_path("query", "load", "unfinished.log")))
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
====

Summary:
crashed:yes, unflushed:no, unfinished:no, leak:no
NG: Please check the display and logs.
        OUTPUT
      end

      sub_test_case("load") do
        def query_log_path(*components)
          fixture_path("query", "load", "flushed", *components)
        end

        def test_target_name
          assert_equal([true, expected],
                       run_command(crash_log_path, query_log_path("target-name.log")))
        end
        def test_only_opened
          assert_equal([true, expected],
                       run_command(crash_log_path, query_log_path("only-opened.log")))
        end
      end
    end

    sub_test_case("unflushed") do
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
====

!!!
!!! [unflushed] Recovery information
!!!
There may be commands that were not flushed between 2000-01-01T00:00:00+09:00 and 2000-01-01T12:00:00+09:00.
These commands may not have been written to the database files, so please re-run them.
===
[unflushed] 2000-01-01T00:00:01+09:00: /d/load?table=Data
====

Summary:
crashed:yes, unflushed:yes, unfinished:no, leak:no
NG: Please check the display and logs.
        OUTPUT
      end

      sub_test_case("load") do
        def query_log_path(*components)
          fixture_path("query", "load", "unflushed", *components)
        end

        def test_no_flush
          assert_equal([true, expected],
                       run_command(crash_log_path, query_log_path("no-flush.log")))
        end

        def test_only_opened
          # TODO: Unflushed should be detected.
          # [unflushed] 2000-01-01T00:00:01+09:00: /d/load?table=Data

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
====

Summary:
crashed:yes, unflushed:no, unfinished:no, leak:no
NG: Please check the display and logs.
          OUTPUT
          assert_equal([true, output],
                       run_command(crash_log_path, query_log_path("only-opened.log")))
        end
      end
    end
  end
end
