# coding: utf-8
# Copyright (C) 2019  Kentaro Hayashi <hayashi@clear-code.com>
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

require "groonga-query-log/command/check-performance-regression"

class CheckPerformanceRegressionCommandTest < Test::Unit::TestCase
  include Helper::Path

  def setup
    @command = GroongaQueryLog::Command::CheckPerformanceRegression.new
  end

  def fixture_path(*components)
    super("check-performance-regression", *components)
  end

  sub_test_case("options") do

    MISSING_QUERY_LOG_ERROR = <<-OUTPUT
old query log and new query log must be specified.
    OUTPUT

    def run_command_with_stderr
      actual = ""
      Tempfile.open("redirect-stderr-tmpfile") do |file|
        $stderr.reopen(file)
        yield(file)
        $stderr.flush
        file.rewind
        actual = file.read
      end
      actual
    end

    def test_no_option
      actual = run_command_with_stderr do
        @command.run([])
      end
      assert_equal(MISSING_QUERY_LOG_ERROR, actual)
    end

    def test_too_few_query_logs
      actual = run_command_with_stderr do
        @command.run([
          fixture_path("query1.log")
        ])
      end
      assert_equal(MISSING_QUERY_LOG_ERROR, actual)
    end

    def test_too_many_query_logs
      actual = run_command_with_stderr do
        @command.run([
          fixture_path("query1.log"),
          fixture_path("query2.log"),
          fixture_path("query1.log")
        ])
      end
      assert_equal(MISSING_QUERY_LOG_ERROR, actual)
    end

    def test_nonexistent_input_old_query
      actual = run_command_with_stderr do
        @command.run([
          fixture_path("nonexsistent.log"),
          fixture_path("query2.log")
        ])
      end
      assert_equal(<<-OUTPUT, actual)
query log path doesn't exist: <#{fixture_path("nonexsistent.log")}>
      OUTPUT
    end

    def test_nonexistent_input_new_query
      actual = run_command_with_stderr do
        @command.run([
          fixture_path("query1.log"),
          fixture_path("nonexsistent.log")
        ])
      end
      assert_equal(<<-OUTPUT, actual)
query log path doesn't exist: <#{fixture_path("nonexsistent.log")}>
      OUTPUT
    end

    def test_output
      path = "/tmp/output"
      @command.run([
        "--slow-response-ratio=0",
        "--slow-operation-ratio=0",
        "--slow-response-threshold=0",
        "--slow-operation-threshold=0",
        "--output=#{path}",
        fixture_path("query1.log"),
        fixture_path("query2.log")
      ])
      expected = <<-OUTPUT
Query: select --table Site --limit 0
  Before(average): 12000000 (nsec) After(average): 14000000 (nsec) Ratio: (+16.67% +0.00sec/+2.00msec/+2000.00usec/+2000000.00nsec)
  Operations:
    Operation: select Before(average): 5000000 (nsec) After(average): 6000000 (nsec) Ratio: (+20.00% +0.00sec/+1.00msec/+1000.00usec/+1000000.00nsec) Context: 
Summary: slow response: 1/1(100.00%) slow operation: 1/2(50.00%) cached: 0
      OUTPUT
      File.open(path, "r") do |file|
        assert_equal(expected, file.read)
      end
      File.unlink(path)
    end

    def test_n_query
      output = StringIO.new
      options = {:output => output}
      command = GroongaQueryLog::Command::CheckPerformanceRegression.new(options)
      command.run([
        "--n-entries=1",
        "--slow-response-ratio=0",
        "--slow-operation-ratio=0",
        "--slow-response-threshold=0",
        "--slow-operation-threshold=0",
        fixture_path("nquery.log"),
        fixture_path("nquery2.log")
      ])
      expected = <<-OUTPUT
Query: select --table Site --filter \"_id >= 4 && _id <= 6\"
  Before(average): 70000000 (nsec) After(average): 90000000 (nsec) Ratio: (+28.57% +0.02sec/+20.00msec/+20000.00usec/+20000000.00nsec)
  Operations:
    Operation: filter Before(average): 40000000 (nsec) After(average): 80000000 (nsec) Ratio: (+100.00% +0.04sec/+40.00msec/+40000.00usec/+40000000.00nsec) Context: #<accessor _id(Site)> greater_equal 4
    Operation: filter Before(average): 10000000 (nsec) After(average): 20000000 (nsec) Ratio: (+100.00% +0.01sec/+10.00msec/+10000.00usec/+10000000.00nsec) Context: #<accessor _id(Site)> less_equal 6
    Operation: select Before(average): 10000000 (nsec) After(average): 20000000 (nsec) Ratio: (+100.00% +0.01sec/+10.00msec/+10000.00usec/+10000000.00nsec) Context: 
    Operation: output Before(average): 10000000 (nsec) After(average): 20000000 (nsec) Ratio: (+100.00% +0.01sec/+10.00msec/+10000.00usec/+10000000.00nsec) Context: 
Summary: slow response: 1/1(100.00%) slow operation: 4/4(100.00%) cached: 0
      OUTPUT
      assert_equal(expected, output.string)
    end
  end

  sub_test_case(".new") do
    def test_output
      output = StringIO.new
      options = {:output => output}
      command = GroongaQueryLog::Command::CheckPerformanceRegression.new(options)
      command.run([
        "--slow-response-ratio=0.0",
        "--slow-operation-ratio=0.0",
        "--slow-response-threshold=0.0",
        "--slow-operation-threshold=0.0",
        fixture_path("query1.log"),
        fixture_path("query2.log")
      ])
      expected = <<-OUTPUT
Query: select --table Site --limit 0
  Before(average): 12000000 (nsec) After(average): 14000000 (nsec) Ratio: (+16.67% +0.00sec/+2.00msec/+2000.00usec/+2000000.00nsec)
  Operations:
    Operation: select Before(average): 5000000 (nsec) After(average): 6000000 (nsec) Ratio: (+20.00% +0.00sec/+1.00msec/+1000.00usec/+1000000.00nsec) Context: 
Summary: slow response: 1/1(100.00%) slow operation: 1/2(50.00%) cached: 0
      OUTPUT
      assert_equal(expected, output.string)
    end
  end

  sub_test_case("ratio") do
    def test_response_filtered
      output = StringIO.new
      options = {:output => output}
      command = GroongaQueryLog::Command::CheckPerformanceRegression.new(options)
      command.run([
        "--slow-response-ratio=20",
        "--slow-operation-ratio=0",
        "--slow-response-threshold=0",
        "--slow-operation-threshold=0",
        fixture_path("query1.log"),
        fixture_path("query2.log")
      ])
      expected = "Summary: slow response: 0/1(0.00%) slow operation: 0/0(NaN%) cached: 0\n"
      assert_equal(expected, output.string)
    end

    def test_operation_filtered
      output = StringIO.new
      options = {:output => output}
      command = GroongaQueryLog::Command::CheckPerformanceRegression.new(options)
      command.run([
        "--slow-response-ratio=0",
        "--slow-operation-ratio=10",
        "--slow-response-threshold=0",
        "--slow-operation-threshold=0",
        fixture_path("query1.log"),
        fixture_path("query2.log")
      ])
      expected = <<-OUTPUT
Query: select --table Site --limit 0
  Before(average): 12000000 (nsec) After(average): 14000000 (nsec) Ratio: (+16.67% +0.00sec/+2.00msec/+2000.00usec/+2000000.00nsec)
  Operations:
    Operation: select Before(average): 5000000 (nsec) After(average): 6000000 (nsec) Ratio: (+20.00% +0.00sec/+1.00msec/+1000.00usec/+1000000.00nsec) Context: 
Summary: slow response: 1/1(100.00%) slow operation: 1/2(50.00%) cached: 0
      OUTPUT
      assert_equal(expected, output.string)
    end
  end

  sub_test_case("threshold") do
    def test_response_threshold
      output = StringIO.new
      options = {:output => output}
      command = GroongaQueryLog::Command::CheckPerformanceRegression.new(options)
      command.run([
        "--slow-response-ratio=0",
        "--slow-operation-ratio=0",
        "--slow-response-threshold=0.02",
        "--slow-operation-threshold=0",
        fixture_path("query1.log"),
        fixture_path("query2.log")
      ])
      expected = "Summary: slow response: 0/1(0.00%) slow operation: 0/0(NaN%) cached: 0\n"
      assert_equal(expected, output.string)
    end

    def test_operation_threshold
      output = StringIO.new
      options = {:output => output}
      command = GroongaQueryLog::Command::CheckPerformanceRegression.new(options)
      command.run([
        "--slow-response-ratio=0",
        "--slow-operation-ratio=0",
        "--slow-response-threshold=0",
        "--slow-operation-threshold=0.001",
        fixture_path("query1.log"),
        fixture_path("query2.log")
      ])
      expected = <<-OUTPUT
Query: select --table Site --limit 0
  Before(average): 12000000 (nsec) After(average): 14000000 (nsec) Ratio: (+16.67% +0.00sec/+2.00msec/+2000.00usec/+2000000.00nsec)
  Operations:
    Operation: select Before(average): 5000000 (nsec) After(average): 6000000 (nsec) Ratio: (+20.00% +0.00sec/+1.00msec/+1000.00usec/+1000000.00nsec) Context: 
Summary: slow response: 1/1(100.00%) slow operation: 1/2(50.00%) cached: 0
      OUTPUT
      assert_equal(expected, output.string)
    end
  end

  sub_test_case("cache") do
    def setup
      @output = StringIO.new
      options = {:output => @output}
      @command = GroongaQueryLog::Command::CheckPerformanceRegression.new(options)
    end

    def test_ignored_cache
      @command.run([
        "--slow-response-ratio=0",
        "--slow-operation-ratio=0",
        "--slow-response-threshold=0",
        fixture_path("cache.log"),
        fixture_path("cache.log")
      ])
      expected = "Summary: slow response: 0/0(NaN%) slow operation: 0/0(NaN%) cached: 1\n"
      assert_equal(expected, @output.string)
    end
  end
end