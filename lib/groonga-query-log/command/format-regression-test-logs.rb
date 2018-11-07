# Copyright (C) 2014-2018  Kouhei Sutou <kou@clear-code.com>
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
require "tempfile"
require "pp"
require "optparse"
require "json"

require "groonga/command/parser"

require "groonga-query-log/version"

module GroongaQueryLog
    module Command
      class FormatRegressionTestLogs
        def initialize
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
              puts("invalid encoding line")
              puts("#{path}:#{input.lineno}:#{line}")
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
            puts(command)
            puts("failed to parse old response: #{$!.message}")
            puts(response_old)
            valid = false
          end

          begin
            JSON.parse(response_new)
          rescue JSON::ParserError
            puts(command)
            puts("failed to parse new response: #{$!.message}")
            puts(response_new)
            valid = false
          end

          valid
        end

        def report_diff(command, response_old, response_new)
          return if response_old == response_new

          Tempfile.open("response-old") do |response_old_file|
            PP.pp(JSON.parse(response_old), response_old_file)
            response_old_file.flush
            Tempfile.open("response-new") do |response_new_file|
              PP.pp(JSON.parse(response_new), response_new_file)
              response_new_file.flush
              report_command(command)
              system("diff",
                     "--label=old",
                     "--label=new",
                     "-u",
                     response_old_file.path, response_new_file.path)
            end
          end
        end

        def report_error(command, message, backtrace)
          report_command(command)
          puts("Error: #{message}")
          puts("Backtrace:")
          puts(backtrace)
        end

        def report_command(command)
          puts("Command:")
          puts(command)
          parsed_command = Groonga::Command::Parser.parse(command)
          puts("Name: #{parsed_command.name}")
          puts("Arguments:")
          sorted_arguments = parsed_command.arguments.sort_by do |key, value|
            key
          end
          sorted_arguments.each do |key, value|
            puts("  #{key}: #{value}")
          end
        end
      end
    end
end
