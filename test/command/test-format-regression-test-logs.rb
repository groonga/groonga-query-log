# -*- coding: utf-8 -*-
#
# Copyright (C) 2014  Kouhei Sutou <kou@clear-code.com>
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

require "groonga-query-log/command/format-regression-test-logs"

class FormatRegressionTestLogsCommandTest < Test::Unit::TestCase
  include Helper::Path

  def setup
    @command = GroongaQueryLog::Command::FormatRegressionTestLogs.new
  end

  def run_command(command_line)
    stdout = $stdout.dup
    output = Tempfile.open("output")
    $stdout.reopen(output)
    succees = @command.run(command_line)
    output.rewind
    [succees, output.read]
  ensure
    $stdout.reopen(stdout)
  end

  def fixture_path(*components)
    super("regression-test-logs", *components)
  end

  def test_nothing
    input = Tempfile.new("format-regression-test-logs")
    assert_equal([true, ""],
                 run_command([input.path]))
  end

  def test_command_format
    output = <<-OUTPUT
select Logs
Name: select
Arguments:
  table: Logs
--- old
+++ new
@@ -1,4 +1,4 @@
 [[[2],
   [[\"_id\", \"UInt32\"], [\"message\", \"Text\"]],
   [1, \"log message1\"],
-  [2, \"log message2\"]]]
+  [3, \"log message3\"]]]
    OUTPUT
    assert_equal([true, output],
                 run_command([fixture_path("command-format.log")]))
  end

  def test_url_format
    output = <<-OUTPUT
/d/select?table=Logs&match_columns=message&query=%E7%84%BC%E8%82%89
Name: select
Arguments:
  match_columns: message
  query: 焼肉
  table: Logs
--- old
+++ new
@@ -1,4 +1,4 @@
 [[[2],
   [[\"_id\", \"UInt32\"], [\"message\", \"Text\"]],
   [1, \"log message1: 焼肉\"],
-  [2, \"log message2: 焼肉\"]]]
+  [3, \"log message3: 焼肉\"]]]
    OUTPUT
    assert_equal([true, output],
                 run_command([fixture_path("url-format.log")]))
  end
end
