# Copyright (C) 2019  Kentaro Hayashi <hayashi@clear-code.com>
# Copyright (C) 2019  Horimoto Yasuhiro <horimoto@clear-code.com>
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

  def run_command(*arguments)
    output = StringIO.new
    options = {:output => output}
    command = GroongaQueryLog::Command::CheckPerformanceRegression.new(options)
    command.run(arguments)
    output.string
  end

  sub_test_case("options") do
    MISSING_QUERY_LOG_ERROR = <<-OUTPUT
old query log and new query log must be specified.
    OUTPUT

    def run_command_with_stderr
      begin
        output = StringIO.new
        $stderr = output
        yield
        output.string
      ensure
        $stderr = STDERR
      end
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
      Tempfile.open('test_output') do |output|
        @command.run([
                       "--slow-query-ratio=0",
                       "--slow-query-second=0",
                       "--slow-operation-ratio=0",
                       "--slow-operation-second=0",
                       "--output=#{output.path}",
                       fixture_path("query1.log"),
                       fixture_path("query2.log")
                     ])
        expected = <<-OUTPUT
Query: select --table Site --limit 0
  Mean (old): 12.0msec
  Mean (new): 14.0msec
  Diff:       +2.0msec/+1.17
  Operations:
    Operation[0]: select
      Mean (old): 5.0msec
      Mean (new): 6.0msec
      Diff:       +1.0msec/+1.20
Summary:
  Slow queries:    1/1(100.00%)
  Slow operations: 1/2( 50.00%)
  Caches (old):    0/1(  0.00%)
  Caches (new):    0/1(  0.00%)
      OUTPUT
        assert_equal(expected, output.read)
      end
    end

    def test_n_query
      actual = run_command("--n-entries=1",
                           "--slow-query-ratio=0",
                           "--slow-query-second=0",
                           "--slow-operation-ratio=0",
                           "--slow-operation-second=0",
                           fixture_path("nquery.log"),
                           fixture_path("nquery2.log"))
      expected = <<-OUTPUT
Query: select --table Site --filter "_id >= 4 && _id <= 6"
  Mean (old): 70.0msec
  Mean (new): 90.0msec
  Diff:       +20.0msec/+1.29
  Operations:
    Operation[0]: filter #<accessor _id(Site)> greater_equal 4
      Mean (old): 40.0msec
      Mean (new): 80.0msec
      Diff:       +40.0msec/+2.00
    Operation[1]: filter #<accessor _id(Site)> less_equal 6
      Mean (old): 10.0msec
      Mean (new): 20.0msec
      Diff:       +10.0msec/+2.00
    Operation[2]: select
      Mean (old): 10.0msec
      Mean (new): 20.0msec
      Diff:       +10.0msec/+2.00
    Operation[3]: output
      Mean (old): 10.0msec
      Mean (new): 20.0msec
      Diff:       +10.0msec/+2.00
Summary:
  Slow queries:    1/1(100.00%)
  Slow operations: 4/4(100.00%)
  Caches (old):    0/1(  0.00%)
  Caches (new):    0/1(  0.00%)
      OUTPUT
      assert_equal(expected, actual)
    end
  end

  sub_test_case(".new") do
    def test_output
      actual = run_command("--slow-query-ratio=0.0",
                           "--slow-query-second=0.0",
                           "--slow-operation-ratio=0.0",
                           "--slow-operation-second=0.0",
                           fixture_path("query1.log"),
                           fixture_path("query2.log"))
      expected = <<-OUTPUT
Query: select --table Site --limit 0
  Mean (old): 12.0msec
  Mean (new): 14.0msec
  Diff:       +2.0msec/+1.17
  Operations:
    Operation[0]: select
      Mean (old): 5.0msec
      Mean (new): 6.0msec
      Diff:       +1.0msec/+1.20
Summary:
  Slow queries:    1/1(100.00%)
  Slow operations: 1/2( 50.00%)
  Caches (old):    0/1(  0.00%)
  Caches (new):    0/1(  0.00%)
      OUTPUT
      assert_equal(expected, actual)
    end
  end

  sub_test_case("query-ratio") do
    def test_filtered
      actual = run_command("--slow-query-ratio=2",
                           "--slow-query-second=0",
                           "--slow-operation-ratio=0",
                           "--slow-operation-second=0",
                           fixture_path("query1.log"),
                           fixture_path("query2.log"))
      expected = <<-OUTPUT
Summary:
  Slow queries:    0/1(  0.00%)
  Slow operations: 0/0(  0.00%)
  Caches (old):    0/1(  0.00%)
  Caches (new):    0/1(  0.00%)
      OUTPUT
      assert_equal(expected, actual)
    end
  end

  sub_test_case("operation-ratio") do
    def test_filtered
      actual = run_command("--slow-query-ratio=0",
                           "--slow-query-second=0",
                           "--slow-operation-ratio=2",
                           "--slow-operation-second=0",
                           fixture_path("query1.log"),
                           fixture_path("query2.log"))
      expected = <<-OUTPUT
Query: select --table Site --limit 0
  Mean (old): 12.0msec
  Mean (new): 14.0msec
  Diff:       +2.0msec/+1.17
  Operations:
Summary:
  Slow queries:    1/1(100.00%)
  Slow operations: 0/2(  0.00%)
  Caches (old):    0/1(  0.00%)
  Caches (new):    0/1(  0.00%)
      OUTPUT
      assert_equal(expected, actual)
    end
  end

  sub_test_case("query-second") do
    def test_filtered
      actual = run_command("--slow-query-ratio=0",
                           "--slow-query-second=0.02",
                           "--slow-operation-ratio=0",
                           "--slow-operation-second=0",
                           fixture_path("query1.log"),
                           fixture_path("query2.log"))
      expected = <<-OUTPUT
Summary:
  Slow queries:    0/1(  0.00%)
  Slow operations: 0/0(  0.00%)
  Caches (old):    0/1(  0.00%)
  Caches (new):    0/1(  0.00%)
      OUTPUT
      assert_equal(expected, actual)
    end
  end

  sub_test_case("operation-second") do
    def test_filtered
      actual = run_command("--slow-query-ratio=0",
                           "--slow-query-second=0",
                           "--slow-operation-ratio=0",
                           "--slow-operation-second=0.001",
                           fixture_path("query1.log"),
                           fixture_path("query2.log"))
      expected = <<-OUTPUT
Query: select --table Site --limit 0
  Mean (old): 12.0msec
  Mean (new): 14.0msec
  Diff:       +2.0msec/+1.17
  Operations:
    Operation[0]: select
      Mean (old): 5.0msec
      Mean (new): 6.0msec
      Diff:       +1.0msec/+1.20
Summary:
  Slow queries:    1/1(100.00%)
  Slow operations: 1/2( 50.00%)
  Caches (old):    0/1(  0.00%)
  Caches (new):    0/1(  0.00%)
      OUTPUT
      assert_equal(expected, actual)
    end
  end

  sub_test_case("cache") do
    def test_ignored_cache
      actual = run_command("--slow-query-ratio=0",
                           "--slow-operation-ratio=0",
                           "--slow-query-second=0",
                           fixture_path("cache.log"),
                           fixture_path("cache.log"))
      expected = <<-OUTPUT
Summary:
  Slow queries:    0/0(  0.00%)
  Slow operations: 0/0(  0.00%)
  Caches (old):    1/1(100.00%)
  Caches (new):    1/1(100.00%)
      OUTPUT
      assert_equal(expected, actual)
    end
  end

  def test_different_operations
      actual = run_command("--slow-query-ratio=0.0",
                           "--slow-query-second=0.0",
                           "--slow-operation-ratio=0.0",
                           "--slow-operation-second=0.0",
                           fixture_path("different_operations1.log"),
                           fixture_path("different_operations2.log"))
      expected = <<-OUTPUT
Query: select Memos   --output_columns _key,tag   --filter 'all_records() && (tag == \"groonga\" || tag == \"mroonga\" || tag == \"droonga\")'   --sortby _id
  Mean (old): 7.1msec
  Mean (new): 82.8msec
  Diff:       +75.7msec/+11.64
Summary:
  Slow queries:    1/1(100.00%)
  Slow operations: 0/0(  0.00%)
  Caches (old):    0/1(  0.00%)
  Caches (new):    0/1(  0.00%)
      OUTPUT
      assert_equal(expected, actual)
  end
end
