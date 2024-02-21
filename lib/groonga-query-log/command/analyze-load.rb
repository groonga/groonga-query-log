# Copyright (C) 2017-2024  Sutou Kouhei <kou@clear-code.com>
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
    class AnalyzeLoad < CommandLine
      def initialize
        setup_options
        @pending_entry = nil
      end

      # Executes load command analyzer for Groonga's query logs.
      # "groonga-query-log-analyze-load" command run this method.
      #
      # @example
      #   analyze_load = GroongaQueryLog::Command::AnalyzeLoad.new
      #   analyze_load.run("--output", "statistics.csv",
      #                    "query.log")
      #
      # If only paths of query log files are specified,
      # this method prints a result of them to console.
      #
      # @param [Array<String>] arguments arguments for
      #   groonga-query-log-analyze-load. Please execute
      #   `groonga-query-log-analyze-load --help` or see
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
            report_header(output)
            parse(log_paths) do |statistic|
              report_statistic(output, statistic)
            end
            if @pending_entry
              report_entry(output, @pending_entry)
              @pending_entry = nil
            end
          end
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
        @options[:output] = "-"
        @options[:target_commands] = ["select", "load"]

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
        parse_log(parser, log_paths, &process_statistic)
      end

      def report_statistic(output, statistic)
        command = statistic.command
        if command.name == "select"
          process_select_statistic(output, statistic, command)
        else
          process_load_statistic(output, statistic, command)
        end
      end

      def process_select_statistic(output, statistic, select_command)
        return if @pending_entry.nil?

        operations = statistic.operations
        if operations.any? {|operation| operation[:name] == "filter"}
          return
        end
        select_operation = operations.find do |operation|
          operation[:name] == "select"
        end
        return if select_operation.nil?

        return if @pending_entry[2] != select_command[:table]

        @pending_entry[6] = select_operation[:n_records]
        report_entry(output, @pending_entry)
        @pending_entry = nil
      end

      def process_load_statistic(output, statistic, load_command)
        operation = statistic.operations.first
        if operation and operation[:extra]
          extra = operation[:extra]
          extra_counts = extra.scan(/\[(\d+)\]/).flatten.collect(&:to_i)
          n_loaded_records = operation[:n_records]
          n_record_errors = extra_counts[0]
          n_column_errors = extra_counts[1]
          total = extra_counts[2]
        else
          n_loaded_records = nil
          n_record_errors = nil
          n_column_errors = nil
          total = nil
        end
        if n_loaded_records and n_loaded_records > 0
          throughput = statistic.elapsed_in_seconds / n_loaded_records
        else
          throughput = nil
        end
        entry = [
          statistic.start_time.iso8601,
          statistic.elapsed_in_seconds,
          throughput,
          load_command.table,
          n_loaded_records,
          n_record_errors,
          n_column_errors,
          total,
        ]
        if @pending_entry
          report_entry(output, @pending_entry)
          @pending_entry = nil
        end
        if total.nil?
          @pending_entry = entry
        else
          report_entry(output, entry)
        end
      end

      def report_header(output)
        header = [
          "start_time",
          "elapsed",
          "throughput",
          "table",
          "n_loaded_records",
          "n_record_errors",
          "n_column_errors",
          "n_total_records",
        ]
        output.puts(header.join(","))
      end

      def report_entry(output, entry)
        output.puts(entry.join(","))
      end
    end
  end
end
