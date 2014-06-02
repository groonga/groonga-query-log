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
              parse_failed = false
              begin
                JSON.parse(response1)
              rescue JSON::ParserError
                puts(command)
                puts("failed to parse response1: #{$!.message}")
                puts(response1)
                parse_failed = true
              end

              begin
                JSON.parse(response2)
              rescue JSON::ParserError
                puts(command)
                puts("failed to parse response2: #{$!.message}")
                puts(response2)
                parse_failed = true
              end

              next if parse_failed

              next if response1 == response2

              base_name = File.basename(path, ".*")
              Tempfile.open("response1-#{base_name}") do |response1_file|
                PP.pp(JSON.parse(response1), response1_file)
                response1_file.flush
                Tempfile.open("response2-#{base_name}") do |response2_file|
                  PP.pp(JSON.parse(response2), response2_file)
                  response2_file.flush
                  puts(command)
                  system("diff",
                         "-u",
                         response1_file.path, response2_file.path)
                end
              end
            end
          end
        end
      end
    end
  end
end
