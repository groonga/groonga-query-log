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

  def run_command(*command_line)
    super(@command, command_line)
  end

  def test_no_target_logs
    assert_equal([true, ""],
                 run_command())
  end

  def test_not_exist_path
    error = assert_raise(Errno::ENOENT) do
      run_command("/path/to/nonexistent")
    end
    assert_equal("No such file or directory @ rb_sysopen - /path/to/nonexistent",
                 error.message)
  end

  def test_normal
    output = [
      :process,
      :success,
      "99.9.9",
      "2000-01-01T00:00:00+09:00",
      "2000-01-01T00:00:10+09:00",
      nil,
      fixture_path("process", "normal.log"),
      fixture_path("process", "normal.log"),
    ].to_s + "\n"
    assert_equal([true, output],
                 run_command(fixture_path("process", "normal.log"),
                             fixture_path("query", "load-flushed", "only-opened.log")))
  end

  def test_leak
    output = [
      [
        :process,
        :success,
        "99.9.9",
        "2000-01-01T00:00:00+09:00",
        "2000-01-01T00:00:10+09:00",
        nil,
        fixture_path("process", "leak.log"),
        fixture_path("process", "leak.log"),
      ].to_s,
      [
        :leak,
        "99.9.9",
        3,
        "2000-01-01T00:00:10+09:00",
        nil,
        fixture_path("process", "leak.log"),
      ].to_s
    ].join("\n") + "\n"
    assert_equal([true, output],
                 run_command(fixture_path("process", "leak.log"),
                             fixture_path("query", "load-flushed", "only-opened.log")))
  end

  sub_test_case("load and flushed on crash") do
    def test_target_name
      output = [
          [
          :process,
          :crashed,
          "99.9.9",
          "2000-01-01T00:00:00+09:00",
          "2000-01-01T12:00:00+09:00",
          1,
          fixture_path("process", "crash.log"),
          fixture_path("process", "crash.log"),
        ].to_s,
        "Important entries:",
        "2000-01-01T12:00:00+09:00: 1: 00000000: critical: -- CRASHED!!! --",
        "2000-01-01T12:00:00+09:00: 1: 00000000: critical: ...trace",
        "2000-01-01T12:00:00+09:00: 1: 00000000: critical: ----------------",
      ].join("\n") + "\n"
      assert_equal([true, output],
                   run_command(fixture_path("process", "crash.log"),
                               fixture_path("query", "load-flushed", "with-target-name.log")))
    end

    def test_only_opened
      output = [
          [
          :process,
          :crashed,
          "99.9.9",
          "2000-01-01T00:00:00+09:00",
          "2000-01-01T12:00:00+09:00",
          1,
          fixture_path("process", "crash.log"),
          fixture_path("process", "crash.log"),
        ].to_s,
        "Important entries:",
        "2000-01-01T12:00:00+09:00: 1: 00000000: critical: -- CRASHED!!! --",
        "2000-01-01T12:00:00+09:00: 1: 00000000: critical: ...trace",
        "2000-01-01T12:00:00+09:00: 1: 00000000: critical: ----------------",
      ].join("\n") + "\n"
      assert_equal([true, output],
                   run_command(fixture_path("process", "crash.log"),
                               fixture_path("query", "load-flushed", "only-opened.log")))
    end
  end

  sub_test_case("load and unflushed on crash") do
    def test_no_flush
      output = [
          [
          :process,
          :crashed,
          "99.9.9",
          "2000-01-01T00:00:00+09:00",
          "2000-01-01T12:00:00+09:00",
          1,
          fixture_path("process", "crash.log"),
          fixture_path("process", "crash.log"),
        ].to_s,
        "Important entries:",
        "2000-01-01T12:00:00+09:00: 1: 00000000: critical: -- CRASHED!!! --",
        "2000-01-01T12:00:00+09:00: 1: 00000000: critical: ...trace",
        "2000-01-01T12:00:00+09:00: 1: 00000000: critical: ----------------",
        "Unflushed commands in 2000-01-01T00:00:00+09:00/2000-01-01T12:00:00+09:00",
        "2000-01-01T00:00:01+09:00: /d/load?table=Data",
      ].join("\n") + "\n"
      assert_equal([true, output],
                   run_command(fixture_path("process", "crash.log"),
                               fixture_path("query", "load-unflushed", "no-flush.log")))
    end

    def test_only_opened
      output = [
          [
          :process,
          :crashed,
          "99.9.9",
          "2000-01-01T00:00:00+09:00",
          "2000-01-01T12:00:00+09:00",
          1,
          fixture_path("process", "crash.log"),
          fixture_path("process", "crash.log"),
        ].to_s,
        "Important entries:",
        "2000-01-01T12:00:00+09:00: 1: 00000000: critical: -- CRASHED!!! --",
        "2000-01-01T12:00:00+09:00: 1: 00000000: critical: ...trace",
        "2000-01-01T12:00:00+09:00: 1: 00000000: critical: ----------------",
        # Unflushed should be detected.
        # "Unflushed commands in 2000-01-01T00:00:00+09:00/2000-01-01T12:00:00+09:00",
        # "2000-01-01T00:00:01+09:00: /d/load?table=Data",
      ].join("\n") + "\n"
      assert_equal([true, output],
                   run_command(fixture_path("process", "crash.log"),
                               fixture_path("query", "load-unflushed", "only-opened.log")))
    end
  end
end
