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

require "groonga/query-log/extractor"
require "groonga/command"

class TestExtractor < Test::Unit::TestCase
  def setup
    @extractor = Groonga::QueryLog::Extractor.new
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
