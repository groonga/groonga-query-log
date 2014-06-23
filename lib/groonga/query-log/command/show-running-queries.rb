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

require "optparse"
require "time"

require "groonga/query-log/version"
require "groonga/query-log/parser"

module Groonga
  module QueryLog
    module Command
      class ShowRunningQueries
        def initialize
          @timestamp = nil
        end

        def run(command_line)
          input_paths = create_parser.parse(command_line)
          each_parsing_statistic(input_paths) do |statistic|
            timestamp = statistic.start_time.strftime("%Y-%m-%d %H:%M:%S.%6N")
            puts("#{timestamp}:#{statistic.raw_command}")
          end
          true
        end

        private
        def create_parser
          parser = OptionParser.new
          parser.version = VERSION
          parser.banner += " QUERY_LOG"

          parser.separator("")
          parser.separator("Options:")

          parser.on("--base-time=TIME",
                    "Show running queries at TIME",
                    "You can use popular time format for TIME such as W3C-DTF",
                    "(now)") do |timestamp|
            @timestamp = Time.parse(timestamp)
          end
        end

        def each_parsing_statistic(input_paths)
          parser = Parser.new
          catch do |tag|
            input_paths.each do |input_path|
              File.open(input_path) do |input|
                parser.parse(input) do |statistic|
                  next if @timestamp.nil?
                  next if statistic.start_time < @timestamp
                  if statistic.start_time == @timestamp
                    yield(statistic)
                  end
                  throw(tag)
                end
              end
            end
          end
          parser.parsing_statistics.each do |statistic|
            yield(statistic)
          end
        end
      end
    end
  end
end
