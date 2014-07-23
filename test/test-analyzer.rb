# -*- coding: utf-8 -*-
#
# Copyright (C) 2014  Kouhei Sutou <kou@clear-code.com>
# Copyright (C) 2012  Haruka Yoshihara <yoshihara@clear-code.com>
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

require "tempfile"
require "pathname"
require "groonga/query-log/analyzer"

class AnalyzerTest < Test::Unit::TestCase
  setup
  def setup_fixtures
    @fixtures_path = File.join(File.dirname(__FILE__), "fixtures")
    @query_log_path = File.join(@fixtures_path, "query.log")
  end

  def setup
    @analyzer = Groonga::QueryLog::Analyzer.new
  end

  class TestInputFile < self
    def test_multi
      other_query_log_path = File.join(@fixtures_path, "other-query.log")
      actual_result = run_analyzer(@query_log_path, other_query_log_path)
      expected_result_path = File.join(@fixtures_path, "multi.expected")

      assert_equal(File.read(expected_result_path), actual_result)
    end

    def test_no_specified
      assert_raise(Groonga::QueryLog::Analyzer::NoInputError) do
        run_analyzer
      end
    end
  end

  data("console"     => "console",
       "HTML"        => "html",
       "JSON"        => "json",
       "JSON stream" => "json-stream")
  def test_reporter(reporter)
    actual_result = run_analyzer("--reporter", reporter, @query_log_path)
    case reporter
    when "json", "json-stream"
      actual_result = normalize_json(actual_result)
    end

    expected_result = expected_analyzed_query("reporter/#{reporter}.expected")
    assert_equal(expected_result, actual_result)
  end

  def test_n_entries
    actual_result = run_analyzer("--n-entries=1", @query_log_path)
    expected_result = expected_analyzed_query("n_entries.expected")
    assert_equal(expected_result, actual_result)
  end

  data(:asc_elapsed     => "elapsed",
       :asc_start_time  => "start-time",
       :desc_elapsed    => "-elapsed",
       :desc_start_time => "-start-time")
  def test_order(order)
    actual_result = run_analyzer("--order=#{order}", @query_log_path)

    expected_result = expected_analyzed_query("order/#{order}.expected")
    assert_equal(expected_result, actual_result)
  end

  def test_no_report_summary
    actual_result = run_analyzer("--no-report-summary", @query_log_path)
    expected_result = expected_analyzed_query("no-report-summary.expected")
    assert_equal(expected_result, actual_result)
  end

  private
  def run_analyzer(*arguments)
    Tempfile.open("output.actual") do |output|
      arguments << "--output" << output.path
      @analyzer.run(arguments)
      File.read(output.path)
    end
  end

  def normalize_json(json)
    json = json.gsub(/("start_time"):\d+/, "\\1:START_TIME")
    json.gsub(/("last_time"):\d+/, "\\1:LAST_TIME")
  end

  def expected_analyzed_query(file_name)
    File.read(File.join(@fixtures_path, file_name))
  end
end
