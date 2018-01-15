# Copyright (C) 2018  Kouhei Sutou <kou@clear-code.com>
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

require "groonga-query-log"
require "groonga-query-log/command-line"

module GroongaQueryLog
  module Command
    class CheckCrash < CommandLine
      def initialize
        setup_options
      end

      def run(arguments)
        begin
          log_paths = @option_parser.parse!(arguments)
        rescue OptionParser::InvalidOption => error
          $stderr.puts(error)
          return false
        end

        begin
          check(log_paths)
        rescue Interrupt
        rescue Error
          $stderr.puts($!.message)
          return false
        end

        true
      end

      private
      def setup_options
        @options = {}

        @option_parser = OptionParser.new do |parser|
          parser.version = VERSION
          parser.banner += " LOG1 ..."
        end
      end

      def open_output
        if @options[:output] == "-"
          yield($stdout)
        else
          File.open(@options[:output], "w") do |output|
            yield(output)
          end
        end
      end

      def check(log_paths)
        general_log_parser = GroongaLog::Parser.new
        query_log_parser = Parser.new
        general_log_paths = []
        query_log_paths = []
        log_paths.each do |log_path|
          sample_lines = File.open(log_path) do |log_file|
            log_file.each_line.take(10)
          end
          if sample_lines.any? {|line| Parser.target_line?(line)}
            query_log_paths << log_path
          elsif sample_lines.any? {|line| GroongaLog::Parser.target_line?(line)}
            general_log_paths << log_path
          end
        end

        running = true
        general_log_parser.parse_paths(general_log_paths) do |entry|
          # p entry
          case entry.log_level
          when :emergency, :alert, :critical, :error, :warning
            p [entry.log_level, entry.message, entry.timestamp.iso8601]
          end

          case entry.message
          when /\Agrn_init:/
            p [:crashed, entry.timestamp.iso8601] if running
            running = true
          when /\Agrn_fin \(\d+\)\z/
            n_leaks = $1.to_i
            running = false
            p [:leak, n_leask, entry.timestamp.iso8601] unless n_leaks.zero?
          end
        end
        query_log_parser.parse_paths(query_log_paths) do |statistic|
          # p statistic
        end
      end
    end
  end
end
