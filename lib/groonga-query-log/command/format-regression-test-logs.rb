# Copyright (C) 2014-2019  Sutou Kouhei <kou@clear-code.com>
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

require "English"
require "find"
require "pp"
require "optparse"
require "json"

require "diff/lcs"
require "diff/lcs/hunk"
require "groonga/command/parser"

require "groonga-query-log/version"

module GroongaQueryLog
  module Command
    class FormatRegressionTestLogs
      def initialize(options={})
        @output = options[:output] || $stdout
      end

      def run(command_line)
        parser = OptionParser.new
        parser.banner += " PATH1 PATH2 ..."
        parser.version = VERSION
        paths = parser.parse!(command_line)

        if paths.empty?
          format_log($stdin, "-")
        else
          paths.each do |path|
            if File.directory?(path)
              Find.find(path) do |sub_path|
                next unless File.file?(sub_path)
                File.open(sub_path) do |file|
                  format_log(file, sub_path)
                end
              end
            else
              File.open(path) do |file|
                format_log(file, path)
              end
            end
          end
        end
        true
      end

      private
      def format_log(input, path)
        command = nil
        response_old = nil
        response_new = nil
        backtrace = []
        error_message = nil

        input.each_line do |line|
          unless line.valid_encoding?
            @output.puts("invalid encoding line")
            @output.puts("#{path}:#{input.lineno}:#{line}")
            next
          end
          case line
          when /\Acommand: /
            command = $POSTMATCH.chomp
          when /\Aresponse1: /
            response_old = $POSTMATCH.chomp
          when /\Aresponse2: /
            response_new = $POSTMATCH.chomp
            next unless valid_entry?(command, response_old, response_new)
            report_diff(command, response_old, response_new)
          when /\Aerror: /
            error_message = $POSTMATCH.chomp
            report_error(command, error_message, backtrace)
            backtrace.clear
          when /\Abacktrace: /
            backtrace.unshift($POSTMATCH.chomp)
          end
        end
      end

      def valid_entry?(command, response_old, response_new)
        valid = true

        begin
          JSON.parse(response_old)
        rescue JSON::ParserError
          @output.puts(command)
          @output.puts("failed to parse old response: #{$!.message}")
          @output.puts(response_old)
          valid = false
        end

        begin
          JSON.parse(response_new)
        rescue JSON::ParserError
          @output.puts(command)
          @output.puts("failed to parse new response: #{$!.message}")
          @output.puts(response_new)
          valid = false
        end

        valid
      end

      def report_diff(command, response_old, response_new)
        return if response_old == response_new

        report_command(command)

        lines_old = response_to_lines(response_old)
        lines_new = response_to_lines(response_new)
        diffs = Diff::LCS.diff(lines_old, lines_new)

        @output.puts("--- old")
        @output.puts("+++ new")

        old_hunk = nil
        n_lines = 3
        format = :unified
        file_length_difference = 0
        diffs.each do |piece|
          begin
            hunk = Diff::LCS::Hunk.new(lines_old,
                                       lines_new,
                                       piece,
                                       n_lines,
                                       file_length_difference)
            file_length_difference = hunk.file_length_difference

            next unless old_hunk

            if (n_lines > 0) && hunk.overlaps?(old_hunk)
              hunk.merge(old_hunk)
            else
              @output.puts(old_hunk.diff(format))
            end
          ensure
            old_hunk = hunk
          end
        end

        if old_hunk
          @output.puts(old_hunk.diff(format))
        end
      end

      def response_to_lines(response)
        PP.pp(JSON.parse(response), "").lines.collect(&:chomp)
      end

      def report_error(command, message, backtrace)
        report_command(command)
        @output.puts("Error: #{message}")
        @output.puts("Backtrace:")
        @output.puts(backtrace)
      end

      def report_command(command)
        @output.puts("Command:")
        @output.puts(command)
        parsed_command = Groonga::Command::Parser.parse(command)
        @output.puts("Name: #{parsed_command.name}")
        @output.puts("Arguments:")
        sorted_arguments = parsed_command.arguments.sort_by do |key, value|
          key
        end
        sorted_arguments.each do |key, value|
          @output.puts("  #{key}: #{value}")
        end
      end
    end
  end
end
