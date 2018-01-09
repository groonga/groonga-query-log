# Copyright (C) 2011-2018  Kouhei Sutou <kou@clear-code.com>
# Copyright (C) 2012  Haruka Yoshihara <yoshihara@clear-code.com>
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
require "json"

require "groonga-query-log"
require "groonga-query-log/command-line-utils"
require "groonga-query-log/command/analyzer/streamer"
require "groonga-query-log/command/analyzer/sized-statistics"
require "groonga-query-log/command/analyzer/reporter/console"
require "groonga-query-log/command/analyzer/reporter/csv"
require "groonga-query-log/command/analyzer/reporter/html"
require "groonga-query-log/command/analyzer/reporter/json"
require "groonga-query-log/command/analyzer/reporter/json-stream"

module GroongaQueryLog
  module Command
    class Analyzer
      include CommandLineUtils

      class Error < StandardError
      end

      class NoInputError < Error
      end

      class UnsupportedReporter < Error
      end

      def initialize
        setup_options
      end

      # Executes analyzer for Groonga's query logs.
      # "groonga-query-log-analyze" command run this method.
      #
      # @example
      #   analyzer = GroongaQueryLog::Command::Analyzer.new
      #   analyzer.run("--output", "statistics.html",
      #                "--reporter", "html",
      #                "query.log")
      #
      # If only paths of query log files are specified,
      # this method prints a result of them to console with coloring.
      #
      # @param [Array<String>] arguments arguments for
      #   groonga-query-log-analyze. Please execute
      #   "groonga-query-log-analyze --help" or see #setup_options.
      def run(arguments)
        begin
          log_paths = @option_parser.parse!(arguments)
        rescue OptionParser::InvalidOption => error
          $stderr.puts(error)
          return false
        end

        stream = @options[:stream]
        dynamic_sort = @options[:dynamic_sort]
        statistics = SizedStatistics.new
        statistics.apply_options(@options)
        if stream
          reporter = create_reporter(statistics)
          reporter.apply_options(@options)
          streamer = Streamer.new(reporter)
          streamer.start
          process_statistic = lambda do |statistic|
            if @options[:stream_all] or statistic.slow?
              streamer << statistic
            end
          end
        elsif dynamic_sort
          process_statistic = lambda do |statistic|
            statistics << statistic
          end
        else
          full_statistics = []
          process_statistic = lambda do |statistic|
            full_statistics << statistic
          end
        end

        begin
          parse(log_paths, &process_statistic)
        rescue Interrupt
          raise unless stream
        end

        if stream
          streamer.finish
        else
          statistics.replace(full_statistics) unless dynamic_sort

          reporter = create_reporter(statistics)
          reporter.apply_options(@options)
          reporter.report
        end

        true
      end

      private
      def setup_options
        @options = {}
        @options[:n_entries] = 10
        @options[:order] = "-elapsed"
        @options[:color] = :auto
        @options[:output] = "-"
        @options[:slow_operation_threshold] = 0.1
        @options[:slow_response_threshold] = 0.2
        @options[:target_commands] = nil
        @options[:target_tables] = nil
        @options[:reporter] = "console"
        @options[:dynamic_sort] = true
        @options[:stream] = false
        @options[:stream_all] = false
        @options[:report_summary] = true

        @option_parser = OptionParser.new do |parser|
          parser.version = VERSION
          parser.banner += " LOG1 ..."

          parser.on("-n", "--n-entries=N",
                    Integer,
                    "Show top N entries",
                    "(#{@options[:n_entries]})") do |n|
            @options[:n_entries] = n
          end

          available_orders = ["elapsed", "-elapsed", "start-time", "-start-time"]
          parser.on("--order=ORDER",
                    available_orders,
                    "Sort by ORDER",
                    "available values: [#{available_orders.join(', ')}]",
                    "(#{@options[:order]})") do |order|
            @options[:order] = order
          end

          color_options = [
            [:auto, :auto],
            ["-", false],
            ["no", false],
            ["false", false],
            ["+", true],
            ["yes", true],
            ["true", true],
          ]
          parser.on("--[no-]color=[auto]",
                    color_options,
                    "Enable color output",
                    "(#{@options[:color]})") do |color|
            if color.nil?
              @options[:color] = true
            else
              @options[:color] = color
            end
          end

          parser.on("--output=PATH",
                    "Output to PATH.",
                    "'-' PATH means standard output.",
                    "(#{@options[:output]})") do |output|
            @options[:output] = output
          end

          parser.on("--slow-operation-threshold=THRESHOLD",
                    Float,
                    "Use THRESHOLD seconds to detect slow operations.",
                    "(#{@options[:slow_operation_threshold]})") do |threshold|
            @options[:slow_operation_threshold] = threshold
          end

          parser.on("--slow-response-threshold=THRESHOLD",
                    Float,
                    "Use THRESHOLD seconds to detect slow responses.",
                    "(#{@options[:slow_response_threshold]})") do |threshold|
            @options[:slow_response_threshold] = threshold
          end

          parser.on("--target-commands=COMMAND1,COMMAND2,...",
                    Array,
                    "Process only COMMANDS.",
                    "Example: --target-commands=select,logical_select",
                    "Process all commands by default") do |commands|
            @options[:target_commands] = commands
          end

          parser.on("--target-tables=TABLE1,TABLE2,...",
                    Array,
                    "Process only TABLES.",
                    "Example: --target-tables=Items,Users",
                    "Process all tables by default") do |tables|
            @options[:target_tables] = tables
          end

          available_reporters = [
            "console",
            "csv",
            "html",
            "json",
            "json-stream",
          ]
          parser.on("--reporter=REPORTER",
                    available_reporters,
                    "Reports statistics by REPORTER.",
                    "available values: [#{available_reporters.join(', ')}]",
                    "(#{@options[:reporter]})") do |reporter|
            @options[:reporter] = reporter
          end

          parser.on("--[no-]dynamic-sort",
                    "Sorts dynamically.",
                    "Memory and CPU usage reduced for large query log.",
                    "(#{@options[:dynamic_sort]})") do |sort|
            @options[:dynamic_sort] = sort
          end

          parser.on("--[no-]stream",
                    "Outputs analyzed query on the fly.",
                    "NOTE: --n-entries and --order are ignored.",
                    "(#{@options[:stream]})") do |stream|
            @options[:stream] = stream
          end

          parser.on("--[no-]stream-all",
                    "Outputs all analyzed queries in stream mode.",
                    "NOTE: This implies --stream.",
                    "(#{@options[:stream_all]})") do |stream_all|
            @options[:stream] = stream_all
            @options[:stream_all] = stream_all
          end

          parser.on("--[no-]report-summary",
                    "Reports summary at the end.",
                    "(#{@options[:report_summary]})") do |report_summary|
            @options[:report_summary] = report_summary
          end
        end
      end

      def create_reporter(statistics)
        case @options[:reporter]
        when "csv"
          CSVReporter.new(statistics)
        when "html"
          HTMLReporter.new(statistics)
        when "json"
          JSONReporter.new(statistics)
        when "json-stream"
          JSONStreamReporter.new(statistics)
        else
          ConsoleReporter.new(statistics)
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

        parser.parse_paths(log_paths, &process_statistic)
      end
    end
  end
end
