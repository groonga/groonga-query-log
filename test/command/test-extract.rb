# Copyright (C) 2012  Haruka Yoshihara <yoshihara@clear-code.com>
# Copyright (C) 2015-2018  Kouhei Sutou <kou@clear-code.com>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License version 2.1 as published by the Free Software Foundation.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

require "stringio"
require "groonga/command"
require "groonga-query-log/command/extract"

class ExtractCommandTest < Test::Unit::TestCase
  include Helper::Command

  setup
  def setup_fixtures
    @fixtures_path = File.join(File.dirname(__FILE__), "..", "fixtures")
    @query_log_path = File.join(@fixtures_path, "query.log")
  end

  def setup
    @extract_command = GroongaQueryLog::Command::Extract.new
  end

  class TestInputFile < self
    def test_multi
      other_query_log_path = File.join(@fixtures_path, "other-query.log")
      actual_commands = run_extractor(@query_log_path, other_query_log_path)
      expected_commands = <<-COMMAND
load --table "Video"
select --output_columns "_key,name" --query "follower:@groonga" --table "Users"
table_create --flags "TABLE_HASH_KEY" --key_type "UInt32" --name "Comments"
column_create --flags "COLUMN_SCALAR" --name "title" --table "Comments" --type "ShortText"
      COMMAND
      assert_equal(expected_commands, actual_commands)
    end

    def test_no_specified
      assert_equal("Error: Please specify input log files.\n",
                   run_extractor)
    end
  end

  class TestUnifyFormat < self
    def test_commands
      actual_commands = run_extractor(@query_log_path,
                                      "--unify-format", "command")

      expected_commands = <<-COMMAND
load --table "Video"
select --output_columns "_key,name" --query "follower:@groonga" --table "Users"
      COMMAND
      assert_equal(expected_commands, actual_commands)
    end

    def test_uri
      actual_commands = run_extractor(@query_log_path,
                                      "--unify-format", "uri")
      expected_commands = <<-COMMAND
/d/load?table=Video
/d/select?output_columns=_key%2Cname&query=follower%3A%40groonga&table=Users
      COMMAND
      assert_equal(expected_commands, actual_commands)
    end

    def test_not_unify
      actual_commands = run_extractor(@query_log_path)
      expected_commands = <<-COMMAND
load --table "Video"
select --output_columns "_key,name" --query "follower:@groonga" --table "Users"
      COMMAND
      assert_equal(expected_commands, actual_commands)
    end
  end

  def test_command
    actual_command = run_extractor(@query_log_path, "--command", "load")
    expected_command = <<-COMMAND
load --table "Video"
    COMMAND

    assert_equal(expected_command, actual_command)
  end

  def test_exclude_command
    actual_command = run_extractor(@query_log_path, "--exclude-command", "load")
    expected_command = <<-COMMAND
select --output_columns "_key,name" --query "follower:@groonga" --table "Users"
    COMMAND

    assert_equal(expected_command, actual_command)
  end

  private
  def run_extractor(*arguments)
    Tempfile.open("extract.output") do |output|
      open_error_output do |error|
        arguments << "--output" << output.path
        if @extract_command.run(arguments)
          File.read(output.path)
        else
          File.read(error.path)
        end
      end
    end
  end

  class TestExtract < self
    def setup
      super
      @log = <<-LOG
2012-12-12 17:39:17.628846|0x7fff786aa2b0|>select --table Users --query follower:@groonga --output_columns _key,name
2012-12-12 17:39:17.629676|0x7fff786aa2b0|:000000000842953 filter(2)
2012-12-12 17:39:17.629709|0x7fff786aa2b0|:000000000870900 select(2)
2012-12-12 17:39:17.629901|0x7fff786aa2b0|:000000001066752 output(2)
2012-12-12 17:39:17.630052|0x7fff786aa2b0|<000000001217140 rc=0
     LOG
    end

    def test_command_format
      @extract_command.options.unify_format = "command"
      expected_formatted_command = <<-COMMAND
select --output_columns "_key,name" --query "follower:@groonga" --table "Users"
      COMMAND

      assert_equal(expected_formatted_command, extract)
    end

    def test_uri_format
      @extract_command.options.unify_format = "uri"
      expected_formatted_command = "/d/select?output_columns=_key%2Cname" +
                                     "&query=follower%3A%40groonga" +
                                     "&table=Users\n"
      assert_equal(expected_formatted_command, extract)
    end

    def test_not_unify
      @extract_command.options.unify_format = nil
      expected_formatted_command = <<-COMMAND
select --output_columns "_key,name" --query "follower:@groonga" --table "Users"
      COMMAND

      assert_equal(expected_formatted_command, extract)
    end

    private
    def extract
      input = Tempfile.new(["groonga-query", ".log"])
      input.puts(@log)
      input.close
      output = StringIO.new
      @extract_command.send(:extract, [input.path], output)
      output.string
    end
  end

  class TestTarget < self
    def test_include
      @extract_command.options.commands = ["register"]
      assert_true(target?("register"))
      assert_false(target?("dump"))
    end

    def test_exclude
      @extract_command.options.exclude_commands = ["dump"]
      assert_true(target?("register"))
      assert_false(target?("dump"))
    end

    def test_not_specified
      assert_true(target?("register"))
      assert_true(target?("dump"))
    end

    def test_regular_expression_include
      @extract_command.options.commands = [/table/]
      assert_true(target?("table_create"))
      assert_false(target?("dump"))
    end

    def test_regular_expression_exclude
      @extract_command.options.exclude_commands = [/table/]
      assert_false(target?("table_create"))
      assert_true(target?("dump"))
    end

    private
    def target?(name)
      command_class = Groonga::Command.find(name)
      command = command_class.new(name, [])
      @extract_command.send(:target?, command)
    end
  end
end
