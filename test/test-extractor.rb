#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
#
# Copyright (C) 2012  Haruka Yoshihara <yoshihara@clear-code.com>
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
require "groonga/query-log/extractor"

class TestExtractor < Test::Unit::TestCase
  def setup
    @extractor = Groonga::QueryLog::Extractor.new
  end

  class TestExtract < self
    def setup
      super
      @log = <<-EOL
2012-12-12 17:39:17.628846|0x7fff786aa2b0|>select --table Users --query follower:@groonga --output_columns _key,name
2012-12-12 17:39:17.629676|0x7fff786aa2b0|:000000000842953 filter(2)
2012-12-12 17:39:17.629709|0x7fff786aa2b0|:000000000870900 select(2)
2012-12-12 17:39:17.629901|0x7fff786aa2b0|:000000001066752 output(2)
2012-12-12 17:39:17.630052|0x7fff786aa2b0|<000000001217140 rc=0
EOL
    end

    def test_command_format
      @extractor.options.unify_format = "command"
      expected_fommated_command = "select --output_columns \"_key,name\""+
                                    " --query \"follower:@groonga\"" +
                                    " --table \"Users\"\n"
      assert_equal(expected_fommated_command, extract)
    end

    def test_uri_format
      @extractor.options.unify_format = "uri"
      expected_fommated_command = "/d/select?output_columns=_key%2Cname" +
                                    "&query=follower%3A%40groonga" +
                                    "&table=Users\n"
      assert_equal(expected_fommated_command, extract)
    end

    def test_not_unify
      @extractor.options.unify_format = nil
      expected_fommated_command = "select --table Users" +
                                  " --query follower:@groonga" +
                                  " --output_columns _key,name\n"
      assert_equal(expected_fommated_command, extract)
    end

    private
    def extract
      output = StringIO.new
      @extractor.send(:extract, @log, output)
      output.string
    end
  end

  class TestTarget < self
    def test_include
      @extractor.options.commands = ["register"]
      assert_true(target?("register"))
      assert_false(target?("dump"))
    end

    def test_exclude
      @extractor.options.exclude_commands = ["dump"]
      assert_true(target?("register"))
      assert_false(target?("dump"))
    end

    def test_not_specified
      assert_true(target?("register"))
      assert_true(target?("dump"))
    end

    def test_regular_expression_include
      @extractor.options.commands = [/table/]
      assert_true(target?("table_create"))
      assert_false(target?("dump"))
    end

    def test_regular_expression_exclude
      @extractor.options.exclude_commands = [/table/]
      assert_false(target?("table_create"))
      assert_true(target?("dump"))
    end

    private
    def target?(name)
      command_class = Groonga::Command.find(name)
      command = command_class.new(name, [])
      @extractor.send(:target?, command)
    end
  end
end
