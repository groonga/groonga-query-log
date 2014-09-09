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

class IncompatibilityDetectorTest < Test::Unit::TestCase
  def detect(command)
    query_log = <<-LOG
2012-12-12 17:39:17.628846|0x7fff786aa2b0|>#{command}
2012-12-12 17:39:17.630052|0x7fff786aa2b0|<000000001217140 rc=0
    LOG
    statistic = parse_query_log(query_log)
    @detector.detect(statistic)
  end

  def parse_query_log(query_log)
    parser = Groonga::QueryLog::Parser.new
    parser.parse(query_log) do |statistic|
      return statistic
    end
  end

  sub_test_case("version1") do
    def setup
      @detector = Groonga::QueryLog::IncompatibilityDetector::Version1.new
    end
  end

  sub_test_case("version2") do
    def setup
      @detector = Groonga::QueryLog::IncompatibilityDetector::Version2.new
    end

    sub_test_case("select") do
      sub_test_case("output_columns") do
        def test_space_delimiter
          message =
            "select: output_columns: space is used as delimiter: <_id _key>"
          assert_equal([message], detect("select --output_columns '_id _key'"))
        end

        def test_comma_delimiter
          assert_equal([], detect("select --output_columns '_id, _key'"))
        end

        def test_one_element
          assert_equal([], detect("select --output_columns '_id'"))
        end
      end
    end
  end
end
