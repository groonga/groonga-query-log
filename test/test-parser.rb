# -*- coding: utf-8 -*-
#
# Copyright (C) 2011-2012  Kouhei Sutou <kou@clear-code.com>
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

class ParserTest < Test::Unit::TestCase
  private
  def statistics
    statistics = []
    parser = Groonga::QueryLog::Parser.new
    parser.parse(StringIO.new(log)) do |statistic|
      statistics << statistic
    end
    statistics
  end

  def log
    @log
  end

  class StatisticOperationTest < self
    def setup
      @log = <<-EOL
2011-06-02 16:27:04.731685|5091e5c0|>/d/select.join?table=Entries&filter=local_name+%40+%22gsub%22+%26%26+description+%40+%22string%22&sortby=_score&output_columns=_key&drilldown=name,class
2011-06-02 16:27:04.733539|5091e5c0|:000000001849451 filter(15)
2011-06-02 16:27:04.734978|5091e5c0|:000000003293459 filter(13)
2011-06-02 16:27:04.735012|5091e5c0|:000000003327415 select(13)
2011-06-02 16:27:04.735096|5091e5c0|:000000003411824 sort(10)
2011-06-02 16:27:04.735232|5091e5c0|:000000003547265 output(10)
2011-06-02 16:27:04.735606|5091e5c0|:000000003921419 drilldown(3)
2011-06-02 16:27:04.735762|5091e5c0|:000000004077552 drilldown(2)
2011-06-02 16:27:04.735808|5091e5c0|<000000004123726 rc=0
EOL
    end

    def test_context
      operations = statistics.first.operations.collect do |operation|
        [operation[:name], operation[:context]]
      end
      expected = [
        ["filter", "local_name @ \"gsub\""],
        ["filter", "description @ \"string\""],
        ["select", nil],
        ["sort", "_score"],
        ["output", "_key"],
        ["drilldown", "name"],
        ["drilldown", "class"],
      ]
      assert_equal(expected, operations)
    end

    def test_n_records
      operations = statistics.first.operations.collect do |operation|
        [operation[:name], operation[:n_records]]
      end
      expected = [
        ["filter", 15],
        ["filter", 13],
        ["select", 13],
        ["sort", 10],
        ["output", 10],
        ["drilldown", 3],
        ["drilldown", 2],
      ]
      assert_equal(expected, operations)
    end
  end
end
