# Copyright (C) 2017  Kouhei Sutou <kou@clear-code.com>
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
require "groonga-query-log/command-line-utils"

module GroongaQueryLog
  module Command
    class LoadAnalyzer
      include CommandLineUtils

      class Error < StandardError
      end

      class NoInputError < Error
      end

      def initialize
        setup_options
      end

      # Executes load command analyzer for Groonga's query logs.
      # "groonga-query-log-load-analyze" command run this method.
      #
      # @example
      #   analyzer = GroongaQueryLog::Command::LoadAnalyzer.new
      #   analyzer.run("--output", "statistics.csv",
      #                "query.log")
      #
      # If only paths of query log files are specified,
      # this method prints a result of them to console.
      #
      # @param [Array<String>] arguments arguments for
      #   groonga-query-log-load-analyze. Please execute
      #   `groonga-query-log-load-analyze --help` or see
      #   #setup_options.
      def run(arguments)
        begin
          log_paths = @option_parser.parse!(arguments)
        rescue OptionParser::InvalidOption => error
          $stderr.puts(error)
          return false
        end

        begin
          open_output do |output|
            parse(log_paths) do |statistic|
              report_statistic(output, statistic)
            end
          end
        rescue Interrupt
        end

        true
      end

      private
      def setup_options
        @options = {}
        @options[:output] = "-"
        @options[:target_commands] = ["load"]

        @option_parser = OptionParser.new do |parser|
          parser.version = VERSION
          parser.banner += " LOG1 ..."

          parser.on("--output=PATH",
                    "Output to PATH.",
                    "'-' PATH means standard output.",
                    "(#{@options[:output]})") do |output|
            @options[:output] = output
          end
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

      def parse(log_paths, &process_statistic)
        parser = Parser.new(@options)
        if log_paths.empty?
          unless log_via_stdin?
            raise(NoInputError, "Error: Please specify input log files.")
          end
          parser.parse($stdin, &process_statistic)
        end

        log_paths.each do |log_path|
          File.open(log_path) do |log|
            parser.parse(log, &process_statistic)
          end
        end
      end

      def report_statistic(output, statistic)
        load_command = statistic.command
        operation = statistic.operations.first
        extra = operation[:extra] || ""
        extra_counts = extra.scan(/\[(\d+)\]/).flatten.collect(&:to_i)
        n_record_errors = extra_counts[0]
        n_column_errors = extra_counts[1]
        total = extra_counts[2]
        entry = [
          statistic.elapsed_in_seconds,
          load_command.table,
          operation[:n_records],
          n_record_errors,
          n_column_errors,
          total,
        ]
        output.puts(entry.join(","))
      end
    end
  end
end
