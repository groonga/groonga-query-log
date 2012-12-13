# -*- coding: utf-8 -*-
#
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

require "stringio"
require "tempfile"
require "pathname"
require "groonga/query-log/analyzer"

class AnalyzerTest < Test::Unit::TestCase
  setup
  def setup_fixtures
    @fixture_path = File.join(File.dirname(__FILE__), "fixtures")
    @query_log_path = File.join(@fixture_path, "query.log")
  end

  def setup
    @analyzer = Groonga::QueryLog::Analyzer.new
  end

  data(:console => "console", :html => "html", :json => "json")
  def test_reporter(reporter)
    actual_result = run_analyzer("--reporter", reporter, @query_log_path)
    actual_result = normalize_json(actual_result) if reporter == "json"

    expected_result = expected_analyzed_query("output/#{reporter}.expected")
    assert_equal(expected_result, actual_result)
  end

  def test_n_entries
    actual_result = run_analyzer("--n-entries=1", @query_log_path)
    expected_result = expected_analyzed_query("n_entries.expected")
    assert_equal(expected_result, actual_result)
  end

  private
  def run_analyzer(*arguments)
    @output = Tempfile.new("output.actual").path
    arguments << "--output" << @output
    @analyzer.run(*arguments)
    File.read(@output)
  end

  def normalize_json(json_string)
    json_string = json_string.gsub(/(\"start_time\"):\d+/,
                                   "\\1:START_TIME")
    json_string.gsub(/(\"last_time\"):\d+/, "\\1:LAST_TIME")
  end

  def expected_analyzed_query(file_name)
    File.read(File.join(@fixture_path, file_name))
  end
end
