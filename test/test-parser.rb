# Copyright (C) 2011-2019  Kouhei Sutou <kou@clear-code.com>
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
  def test_load
    statistics = parse(<<-LOG)
2012-12-13 11:15:21.628105|0x7fff148c8a50|>load --table Video
2012-12-13 11:15:21.645119|0x7fff148c8a50|<000000017041150 rc=0
    LOG
    parsed_command = statistics.first.command
    assert_instance_of(Groonga::Command::Load, parsed_command)
  end

  def test_ignore_invalid_line
    garbage = "\x80"
    statistics = parse(<<-LOG)
2012-12-13 11:15:20.628105|0x7fff148c8a50|>#{garbage}
2012-12-13 11:15:21.628105|0x7fff148c8a50|>load --table Video
2012-12-13 11:15:21.645119|0x7fff148c8a50|<000000017041150 rc=0
    LOG
    parsed_command = statistics.first.command
    assert_instance_of(Groonga::Command::Load, parsed_command)
  end

  def test_no_command_name_path
    statistics = parse(<<-LOG)
2012-12-13 11:15:20.628105|0x7fff148c8a50|>/
2012-12-13 11:15:21.645119|0x7fff148c8a50|<000000017041150 rc=0
    LOG
    assert_equal([nil], statistics.collect(&:command))
  end

  def test_no_command_to_hash
    statistics = parse(<<-LOG)
2012-12-13 11:15:20.628105|0x7fff148c8a50|>/
2012-12-13 11:15:21.645119|0x7fff148c8a50|<000000017041150 rc=0
    LOG
    expected = {
      "raw" => "/"
    }
    assert_equal(expected, statistics[0].to_hash["command"])
  end

  private
  def parse(log)
    statistics = []
    parser = GroongaQueryLog::Parser.new
    parser.parse(StringIO.new(log)) do |statistic|
      statistics << statistic
    end
    statistics
  end

  class StatisticOperationTest < self
    def setup
      @statistics = parse(<<-LOG)
2011-06-02 16:27:04.731685|5091e5c0|>/d/select.join?table=Entries&filter=local_name+%40+%22gsub%22+%26%26+description+%40+%22string%22&sortby=_score&output_columns=_key&drilldown=name,class
2011-06-02 16:27:04.733539|5091e5c0|:000000001849451 filter(15)
2011-06-02 16:27:04.734978|5091e5c0|:000000003293459 filter(13)
2011-06-02 16:27:04.735012|5091e5c0|:000000003327415 select(13)
2011-06-02 16:27:04.735096|5091e5c0|:000000003411824 sort(10)
2011-06-02 16:27:04.735232|5091e5c0|:000000003547265 output(10)
2011-06-02 16:27:04.735606|5091e5c0|:000000003921419 drilldown(3)
2011-06-02 16:27:04.735762|5091e5c0|:000000004077552 drilldown(2)
2011-06-02 16:27:04.735808|5091e5c0|<000000004123726 rc=0
      LOG
      @statistic = @statistics.first
    end

    def test_context
      operations = @statistic.operations.collect do |operation|
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
      operations = @statistic.operations.collect do |operation|
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

  class TestRC < self
    def test_success
      statistics = parse(<<-LOG)
2012-12-13 11:15:21.628105|0x7fff148c8a50|>table_create --name Videos
2012-12-13 11:15:21.645119|0x7fff148c8a50|<000000017041150 rc=0
      LOG
      assert_equal([0], statistics.collect(&:return_code))
    end

    def test_failure
      statistics = parse(<<-LOG)
2012-12-13 11:15:21.628105|0x7fff148c8a50|>table_create --name Videos
2012-12-13 11:15:21.645119|0x7fff148c8a50|<000000017041150 rc=-22
      LOG
      assert_equal([-22], statistics.collect(&:return_code))
    end
  end

  class FormatCompatibilityTest < self
    class DynamicColumnsTest < self
      def test_no_labeled_columns
        statistics = parse(<<-LOG)
2017-05-30 19:11:37.932576|0x7ffc6ae1ba20|>select Items   --columns[price_with_tax].stage initial   --columns[price_with_tax].type UInt32   --columns[price_with_tax].flags COLUMN_SCALAR   --columns[price_with_tax].value 'price * 1.08'   --filter 'price_with_tax > 550'
2017-05-30 19:11:37.976349|0x7ffc6ae1ba20|:000000043784801 filter(3)
2017-05-30 19:11:37.976383|0x7ffc6ae1ba20|:000000043808671 select(3)
2017-05-30 19:11:37.976534|0x7ffc6ae1ba20|:000000043961723 output(3)
2017-05-30 19:11:37.976650|0x7ffc6ae1ba20|<000000044078013 rc=0
        LOG
        operations = statistics.first.operations.collect do |operation|
          [operation[:name], operation[:n_records]]
        end
        expected = [
          ["filter", 3],
          ["select", 3],
          ["output", 3]
        ]
        assert_equal(expected, operations)
      end

      def test_labeled_columns
        statistics = parse(<<-LOG)
2017-05-30 19:11:38.036856|0x7fffb7d8d9b0|>select Items   --columns[price_with_tax].stage initial   --columns[price_with_tax].type UInt32   --columns[price_with_tax].flags COLUMN_SCALAR   --columns[price_with_tax].value 'price * 1.08'   --filter 'price_with_tax > 550'
2017-05-30 19:11:38.037234|0x7fffb7d8d9b0|:000000000381368 columns[price_with_tax](6)
2017-05-30 19:11:38.085663|0x7fffb7d8d9b0|:000000048816481 filter(3)
2017-05-30 19:11:38.085691|0x7fffb7d8d9b0|:000000048837085 select(3)
2017-05-30 19:11:38.085825|0x7fffb7d8d9b0|:000000048972310 output(3)
2017-05-30 19:11:38.085929|0x7fffb7d8d9b0|<000000049076026 rc=0
        LOG
        operations = statistics.first.operations.collect do |operation|
          [operation[:name], operation[:n_records]]
        end
        expected = [
          ["columns[price_with_tax]", 6],
          ["filter", 3],
          ["select", 3],
          ["output", 3]
        ]
        assert_equal(expected, operations)
      end
    end

    class DrilldownTest < self
      def test_no_output_drilldown
        statistics = parse(<<-LOG)
2017-05-31 11:22:19.928613|0x7ffe470b0cc0|>select Memos --drilldown tag
2017-05-31 11:22:19.928705|0x7ffe470b0cc0|:000000000095083 select(4)
2017-05-31 11:22:19.929002|0x7ffe470b0cc0|:000000000393647 output(4)
2017-05-31 11:22:19.929040|0x7ffe470b0cc0|:000000000428917 drilldown(3)
2017-05-31 11:22:19.929109|0x7ffe470b0cc0|<000000000498630 rc=0
        LOG
        operations = statistics.first.operations.collect do |operation|
          [operation[:name], operation[:n_records]]
        end
        expected = [
          ["select", 4],
          ["output", 4],
          ["drilldown", 3]
        ]
        assert_equal(expected, operations)
      end

      def test_output_drilldown
        statistics = parse(<<-LOG)
2017-05-31 11:22:19.977081|0x7ffec4a59cd0|>select Memos --drilldown tag
2017-05-31 11:22:19.977214|0x7ffec4a59cd0|:000000000138164 select(4)
2017-05-31 11:22:19.977381|0x7ffec4a59cd0|:000000000304772 drilldown(3)
2017-05-31 11:22:19.977572|0x7ffec4a59cd0|:000000000495092 output(4)
2017-05-31 11:22:19.977615|0x7ffec4a59cd0|:000000000535908 output.drilldown(3)
2017-05-31 11:22:19.977701|0x7ffec4a59cd0|<000000000623964 rc=0
        LOG
        operations = statistics.first.operations.collect do |operation|
          [operation[:name], operation[:n_records]]
        end
        expected = [
          ["select", 4],
          ["drilldown", 3],
          ["output", 4],
          ["output.drilldown", 3]
        ]
        assert_equal(expected, operations)
      end
    end

    class LabeledDrilldownTest < self
      def test_no_output_drilldown
        statistics = parse(<<-LOG)
2017-05-31 11:22:19.683806|0x7ffc1ee41940|>select Shops   --drilldown[item].keys items   --drilldown[item].sortby price   --drilldown[item].output_columns _key,_nsubrecs,price,price_with_tax   --drilldown[item].columns[price_with_tax].stage initial   --drilldown[item].columns[price_with_tax].type UInt32   --drilldown[item].columns[price_with_tax].flags COLUMN_SCALAR   --drilldown[item].columns[price_with_tax].value 'price * 1.08'   --drilldown[real_price].table item   --drilldown[real_price].keys price_with_tax
2017-05-31 11:22:19.683980|0x7ffc1ee41940|:000000000176192 select(3)
2017-05-31 11:22:19.684356|0x7ffc1ee41940|:000000000553162 output(3)
2017-05-31 11:22:19.684468|0x7ffc1ee41940|:000000000665698 drilldown(6)[item]
2017-05-31 11:22:19.684488|0x7ffc1ee41940|:000000000683901 drilldown(3)[real_price]
2017-05-31 11:22:19.684558|0x7ffc1ee41940|<000000000754417 rc=0
        LOG
        operations = statistics.first.operations.collect do |operation|
          [operation[:name], operation[:n_records]]
        end
        expected = [
          ["select", 3],
          ["output", 3],
          ["drilldown[item]", 6],
          ["drilldown[real_price]", 3]
        ]
        assert_equal(expected, operations)
      end

      def test_output_drilldown
        statistics = parse(<<-LOG)
2017-05-31 11:22:19.758189|0x7ffd1fc97890|>select Shops   --drilldown[item].keys items   --drilldown[item].sortby price   --drilldown[item].output_columns _key,_nsubrecs,price,price_with_tax   --drilldown[item].columns[price_with_tax].stage initial   --drilldown[item].columns[price_with_tax].type UInt32   --drilldown[item].columns[price_with_tax].flags COLUMN_SCALAR   --drilldown[item].columns[price_with_tax].value 'price * 1.08'   --drilldown[real_price].table item   --drilldown[real_price].keys price_with_tax
2017-05-31 11:22:19.758462|0x7ffd1fc97890|:000000000276579 select(3)
2017-05-31 11:22:19.758727|0x7ffd1fc97890|:000000000542224 columns[price_with_tax](6)
2017-05-31 11:22:19.758738|0x7ffd1fc97890|:000000000550409 drilldowns[item](6)
2017-05-31 11:22:19.758806|0x7ffd1fc97890|:000000000619409 drilldowns[real_price](3)
2017-05-31 11:22:19.758915|0x7ffd1fc97890|:000000000729209 output(3)
2017-05-31 11:22:19.759015|0x7ffd1fc97890|:000000000829476 output.drilldowns[item](6)
2017-05-31 11:22:19.759034|0x7ffd1fc97890|:000000000847090 output.drilldowns[real_price](3)
2017-05-31 11:22:19.759103|0x7ffd1fc97890|<000000000916234 rc=0
        LOG
        operations = statistics.first.operations.collect do |operation|
          [operation[:name], operation[:n_records]]
        end
        expected = [
          ["select", 3],
          ["columns[price_with_tax]", 6],
          ["drilldowns[item]", 6],
          ["drilldowns[real_price]", 3],
          ["output", 3],
          ["output.drilldowns[item]", 6],
          ["output.drilldowns[real_price]", 3]
        ]
        assert_equal(expected, operations)
      end
    end
  end

  class NameFieldTest < self
    def test_io_flush
      statistics = parse(<<-LOG)
2019-05-09 18:44:25.983672|0x7fff5e4a3060|>io_flush Lexicon.sources_value --output_type json
2019-05-09 18:44:25.989502|0x7fff5e4a3060|:000000005833721 flush[Lexicon.sources_value]
2019-05-09 18:44:25.989519|0x7fff5e4a3060|:000000005848066 flush[(anonymous:table:dat_key)]
2019-05-09 18:44:25.990491|0x7fff5e4a3060|:000000006820471 flush[(anonymous:column:var_size)]
2019-05-09 18:44:25.990496|0x7fff5e4a3060|:000000006824538 flush[(anonymous:table:hash_key)]
2019-05-09 18:44:25.991425|0x7fff5e4a3060|:000000007753922 flush[(anonymous:column:var_size)]
2019-05-09 18:44:25.991427|0x7fff5e4a3060|:000000007755618 flush[(DB)]
2019-05-09 18:44:25.991431|0x7fff5e4a3060|<000000007759904 rc=0
      LOG
      operations = statistics.first.operations.collect do |operation|
        [operation[:name], operation[:raw_message]]
      end
      expected = [
        ["flush[Lexicon.sources_value]",
         "flush[Lexicon.sources_value]"],
        ["flush[(anonymous:table:dat_key)]",
         "flush[(anonymous:table:dat_key)]"],
        ["flush[(anonymous:column:var_size)]",
         "flush[(anonymous:column:var_size)]"],
        ["flush[(anonymous:table:hash_key)]",
         "flush[(anonymous:table:hash_key)]"],
        ["flush[(anonymous:column:var_size)]",
         "flush[(anonymous:column:var_size)]"],
        ["flush[(DB)]",
         "flush[(DB)]"],
      ]
      assert_equal(expected, operations)
    end
  end

  class ExtraFieldTest < self
    def test_load
      statistics = parse(<<-LOG)
2017-12-11 09:37:04.516938|0x7fffc430dff0|>load --table Numbers
2017-12-11 09:37:04.517993|0x7fffc430dff0|:000000001056310 load(3): [1][2][3]
2017-12-11 09:37:04.517999|0x7fffc430dff0|<000000001061996 rc=-22
      LOG
      operations = statistics.first.operations.collect do |operation|
        [
          operation[:name],
          operation[:n_records],
          operation[:extra],
          operation[:raw_message],
        ]
      end
      expected = [
        ["load", 3, "[1][2][3]", "load(3): [1][2][3]"],
      ]
      assert_equal(expected, operations)
    end
  end
end
