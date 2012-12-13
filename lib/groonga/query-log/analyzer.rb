# -*- coding: utf-8 -*-
#
# Copyright (C) 2011-2012  Kouhei Sutou <kou@clear-code.com>
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

require 'optparse'
require "groonga/query-log/parser"
require "groonga/query-log/analyzer/sized-statistics"

module Groonga
  module QueryLog
    class Analyzer
      class Error < StandardError
      end

      class UnsupportedReporter < Error
      end

      def initialize
        setup_options
      end

      def run(argv=nil)
        log_paths = @option_parser.parse!(argv || ARGV)

        stream = @options[:stream]
        dynamic_sort = @options[:dynamic_sort]
        statistics = SizedStatistics.new
        statistics.apply_options(@options)
        parser = Groonga::QueryLog::Parser.new
        if stream
          streamer = Streamer.new(create_reporter(statistics))
          streamer.start
          process_statistic = lambda do |statistic|
            streamer << statistic
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
        if log_paths.empty?
          parser.parse(ARGF, &process_statistic)
        else
          log_paths.each do |log_path|
            File.open(log_path) do |log|
              parser.parse(log, &process_statistic)
            end
          end
        end
        if stream
          streamer.finish
          return
        end
        statistics.replace(full_statistics) unless dynamic_sort

        reporter = create_reporter(statistics)
        reporter.apply_options(@options)
        reporter.report
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
        @options[:reporter] = "console"
        @options[:dynamic_sort] = true
        @options[:stream] = false
        @options[:report_summary] = true

        @option_parser = OptionParser.new do |parser|
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
                    "Use THRESHOLD seconds to detect slow operations.",
                    "(#{@options[:sloq_response_threshold]})") do |threshold|
            @options[:sloq_response_threshold] = threshold
          end

          available_reporters = ["console", "json", "html"]
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

          parser.on("--[no-]report-summary",
                    "Reports summary at the end.",
                    "(#{@options[:report_summary]})") do |report_summary|
            @options[:report_summary] = report_summary
          end
        end

        def create_reporter(statistics)
          case @options[:reporter]
          when "json"
            require 'json'
            JSONReporter.new(statistics)
          when "html"
            HTMLReporter.new(statistics)
          else
            ConsoleReporter.new(statistics)
          end
        end

        def create_stream_reporter
          case @options[:reporter]
          when "json"
            require 'json'
            Groonga::QueryLog::StreamJSONQueryLogReporter.new
          when "html"
            raise UnsupportedReporter, "HTML reporter doesn't support --stream."
          else
            Groonga::QueryLog::StreamConsoleQueryLogReporter.new
          end
        end
      end
    end
  end
end
