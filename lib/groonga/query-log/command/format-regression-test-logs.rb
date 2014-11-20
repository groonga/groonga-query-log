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

require "English"
require "find"
require "tempfile"
require "pp"
require "optparse"
require "json"

require "groonga/command/parser"

require "groonga/query-log/version"

module Groonga
  module QueryLog
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
          response1 = nil
          response2 = nil

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
              response1 = $POSTMATCH.chomp
            when /\Aresponse2: /
              response2 = $POSTMATCH.chomp
              next unless valid_entry?(command, response1, response2)
              report_diff(command, response1, response2)
            end
          end
        end

        def valid_entry?(command, response1, response2)
          valid = true

          begin
            JSON.parse(response1)
          rescue JSON::ParserError
            puts(command)
            puts("failed to parse response1: #{$!.message}")
            puts(response1)
            valid = false
          end

          begin
            JSON.parse(response2)
          rescue JSON::ParserError
            puts(command)
            puts("failed to parse response2: #{$!.message}")
            puts(response2)
            valid = false
          end

          valid
        end

        def report_diff(command, response1, response2)
          return if response1 == response2

          Tempfile.open("response1") do |response1_file|
            PP.pp(JSON.parse(response1), response1_file)
            response1_file.flush
            Tempfile.open("response2") do |response2_file|
              PP.pp(JSON.parse(response2), response2_file)
              response2_file.flush
              report_command(command)
              system("diff",
                     "--label=old",
                     "--label=new",
                     "-u",
                     response1_file.path, response2_file.path)
            end
          end
        end

        def report_command(command)
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
end
