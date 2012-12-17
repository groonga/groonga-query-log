#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
#
# Copyright (C) 2011  Kouhei Sutou <kou@clear-code.com>
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

require "ostruct"
require "optparse"
require "pathname"
require "groonga/query-log/parser"

module Groonga
  module QueryLog
    class Extractor

      class Error < StandardError
      end

      class NoInputError < Error
      end

      attr_accessor :options
      attr_reader :option_parser

      def initialize
        @options = nil
        @option_parser = nil
        setup_options
      end

      private
      def target?(command)
        name = command.name
        commands = @options.commands
        exclude_commands = @options.exclude_commands

        unless commands.empty?
          return commands.any? {|command| command === name}
        end

        unless exclude_commands.empty?
          return (not exclude_commands.any? {|command| command === name})
        end

        true
      end

      def setup_options
        @options = OpenStruct.new
        @options.unify_format = nil
        @options.commands = []
        @options.exclude_commands = []
        @options.output_path = nil
        @option_parser = OptionParser.new do |parser|
          parser.banner += " QUERY_LOG1 ..."

          available_formats = ["uri", "command"]
          parser.on("--unify-format=FORMAT",
                 available_formats,
                 "Unify command format to FORMAT.",
                 "(#{available_formats.join(', ')})",
                 "[not unify]") do |format|
            @options.unify_format = format
          end

          parser.on("--command=COMMAND",
                 "Extract only COMMAND.",
                 "To extract one or more commands,",
                 "specify this command a number of times.",
                 "Use /.../ as COMMAND to match command with regular expression.",
                 "[all commands]") do |command|
            case command
            when /\A\/(.*)\/(i)?\z/
              @options.commands << Regexp.new($1, $2 == "i")
            when
              @options.commands << command
            end
          end

          parser.on("--exclude-command=COMMAND",
                 "Don't extract COMMAND.",
                 "To ignore one or more commands,",
                 "specify this command a number of times.",
                 "Use /.../ as COMMAND to match command with regular expression.",
                 "[no commands]") do |command|
            case command
            when /\A\/(.*)\/(i)?\z/
              @options.exclude_commands << Regexp.new($1, $2 == "i")
            when
              @options.exclude_commands << command
            end
          end

          parser.on("--output=PATH",
                 "Output to PATH.",
                 "[standard output]") do |path|
            @options.output_path = path
          end
        end
      end

      def extract(log, output)
        parser = Groonga::QueryLog::Parser.new
        parser.parse(log) do |statistic|
          command = statistic.command
          next unless target?(command)
          command_text = nil
          case @options.unify_format
          when "uri"
            command_text = command.to_uri_format
          when "command"
            command_text = command.to_command_format
          else
            command_text = statistic.raw_command
          end
          output.puts(command_text)
        end
      end
    end
  end
end
