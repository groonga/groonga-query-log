# Copyright (C) 2019  Kentaro Hayashi <hayashi@clear-code.com>
# Copyright (C) 2019  Sutou Kouhei <kou@clear-code.com>
# Copyright (C) 2019  Horimoto Yasuhiro <horimoto@clear-code.com>
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

require "json"
require "optparse"

require "groonga-query-log"
require "groonga-query-log/command-line"

require "groonga-query-log/command/analyzer"
require "groonga-query-log/command/analyzer/sized-statistics"

module GroongaQueryLog
  module Command
    class CheckPerformanceRegression < CommandLine
      NSEC_IN_SECONDS = (1000 * 1000 * 1000)
      USEC_IN_SECONDS = (1000 * 1000)
      MSEC_IN_SECONDS = 1000

      def initialize(options={})
        setup_options(options)
      end

      def run(arguments)
        paths = []
        begin
          paths = @option_parser.parse!(arguments)
        rescue OptionParser::InvalidOption => error
          $stderr.puts(error)
          return false
        end

        if paths.size != 2
          $stderr.puts("old query log and new query log must be specified.")
          return false
        end

        old_query_paths = resolve_path(paths[0])
        return false if old_query_paths.nil?
        new_query_paths = resolve_path(paths[1])
        return false if new_query_paths.nil?

        old_statistics = analyze(old_query_paths)
        return false if old_statistics.nil?
        new_statistics = analyze(new_query_paths)
        return false if new_statistics.nil?

        open_output do |output|
          checker = Checker.new(old_statistics,
                                new_statistics,
                                output,
                                @threshold,
                                @target_queries)
          checker.check
        end
      end

      private
      def resolve_path(path)
        if File.directory?(path)
          Dir.glob("#{path}/*.log")
        elsif File.exist?(path)
          [path]
        else
          $stderr.puts("query log path doesn't exist: <#{path}>")
          nil
        end
      end

      def open_output(&block)
        case @output
        when "-"
          yield($stdout)
        when String
          File.open(@output, "w", &block)
        else
          yield(@output)
        end
      end

      def setup_options(options)
        @output = options[:output] || "-"
        @n_entries = -1
        @threshold = Threshold.new
        @target_queries = []

        @option_parser = OptionParser.new do |parser|
          parser.version = VERSION
          parser.banner += " OLD_QUERY_LOG NEW_QUERY_LOG"

          parser.on("-n", "--n-entries=N",
                    Integer,
                    "Analyze N query log entries",
                    "You can use -1 to analyze all query log entries",
                    "(#{@n_entries})") do |n|
            @n_entries = n
          end

          if @output == "-"
            default_output = "stdout"
          else
            default_output = @output
          end
          parser.on("--output=PATH",
                    "Output to PATH.",
                    "(#{default_output})") do |output|
            @output = output
          end

          parser.on("--target-query-file=TARGET_QUERY_FILE",
                    "Analyze matched queries which are listed " +
                    "in specified TARGET_QUERY_FILE.") do |path|
            if File.exist?(path)
              @target_queries = File.readlines(path, chomp: true)
            else
              message = "target query file doesn't exist: <#{path}>"
              raise OptionParser::InvalidOption.new(message)
            end
          end

          parser.on("--slow-query-ratio=RATIO",
                    Float,
                    "Use RATIO as threshold to detect slow queries.",
                    "If MEAN_NEW_ELAPSED_TIME / MEAN_OLD_ELAPSED_TIME AVERAGE",
                    "is larger than RATIO, the query is slow.",
                    "(#{@threshold.query_ratio})") do |ratio|
            @threshold.query_ratio = ratio
          end

          parser.on("--slow-query-second=SECOND",
                    Float,
                    "Use SECOND as threshold to detect slow queries.",
                    "If MEAN_NEW_ELAPSED_TIME - MEAN_OLD_ELAPSED_TIME AVERAGE",
                    "is larger than SECOND, the query is slow.",
                    "(#{@threshold.query_second})") do |second|
            @threshold.query_second = second
          end

          parser.on("--slow-operation-ratio=RATIO",
                    Float,
                    "Use RATIO as threshold to detect slow operations.",
                    "If MEAN_NEW_ELAPSED_TIME / MEAN_OLD_ELAPSED_TIME AVERAGE",
                    "is larger than RATIO, the operation is slow.",
                    "(#{@threshold.operation_ratio})") do |ratio|
            @threshold.operation_ratio = ratio
          end

          parser.on("--slow-operation-second=SECOND",
                    Float,
                    "Use SECOND as threshold to detect slow operations.",
                    "If MEAN_NEW_ELAPSED_TIME - MEAN_OLD_ELAPSED_TIME AVERAGE",
                    "is larger than SECOND, the operation is slow.",
                    "(#{@threshold.operation_second})") do |second|
            @threshold.operation_second = second
          end
        end
      end


      def analyze(log_paths)
        full_statistics = []
        begin
          parser = Parser.new
          parse = parse_log(parser, log_paths)
          parse = parse.first(@n_entries) if @n_entries >= 0
          parse.each do |statistic|
            full_statistics << statistic
          end
        rescue Error
          $stderr.puts($!.message)
          return nil
        end
        full_statistics
      end

      class Threshold
        attr_accessor :query_ratio
        attr_accessor :query_second
        attr_accessor :operation_ratio
        attr_accessor :operation_second
        def initialize
          @query_ratio = 0
          @query_second = 0.2
          @operation_ratio = 0.1
          @operation_second = 0.1
        end

        def slow_query?(diff_sec, diff_ratio)
          return false if diff_sec.zero?
          (diff_sec >= @query_second) and
            (diff_ratio >= @query_ratio)
        end

        def slow_operation?(diff_sec, diff_ratio)
          return false if diff_sec.zero?
          (diff_sec >= @operation_second) and
            (diff_ratio >= @operation_ratio)
        end
      end

      class Statistic
        def initialize(old, new, threshold)
          @old = old
          @new = new
          @threshold = threshold
        end

        def old_elapsed_time
          @old_elapsed_time ||= compute_mean(@old)
        end

        def new_elapsed_time
          @new_elapsed_time ||= compute_mean(@new)
        end

        def diff_elapsed_time
          new_elapsed_time - old_elapsed_time
        end

        def ratio
          @ratio ||= compute_ratio
        end

        private
        def compute_ratio
          if old_elapsed_time.zero?
            if new_elapsed_time.zero?
              0.0
            else
              Float::INFINITY
            end
          else
            new_elapsed_time / old_elapsed_time
          end
        end
      end

      class OperationStatistic < Statistic
        attr_reader :index
        def initialize(operation, index, old, new, threshold)
          super(old, new, threshold)
          @operation = operation
          @index = index
        end

        def name
          @operation[:name]
        end

        def context
          @operation[:context]
        end

        def slow?
          @threshold.slow_operation?(diff_elapsed_time, ratio)
        end

        private
        def compute_mean(operations)
          elapsed_times = operations.collect do |operation|
            operation[:relative_elapsed] / 1000.0 / 1000.0 / 1000.0
          end
          elapsed_times.inject(:+) / elapsed_times.size
        end
      end

      class QueryStatistic < Statistic
        attr_reader :query
        def initialize(query, old, new, threshold)
          super(old, new, threshold)
          @query = query
        end

        def slow?
          @threshold.slow_query?(diff_elapsed_time, ratio)
        end

        def each_operation_statistic
          @old.first.operations.each_with_index do |operation, i|
            old_operations = @old.collect do |statistic|
              statistic.operations[i]
            end
            # TODO: old and new may use different index
            new_operations = @new.collect do |statistic|
              statistic.operations[i]
            end
            operation_statistic = OperationStatistic.new(operation,
                                                         i,
                                                         old_operations,
                                                         new_operations,
                                                         @threshold)
            yield(operation_statistic)
          end
        end

        def same_operations?
          old_operations = []
          @old.collect do |statistic|
             statistic.operations.each do |operation|
               old_operations << operation[:name]
             end
          end

          new_operations = []
          @new.collect do |statistic|
            statistic.operations.each do |operation|
              new_operations << operation[:name]
            end
          end
          old_operations == new_operations
        end

        private
        def compute_mean(statistics)
          elapsed_times = statistics.collect do |statistic|
            statistic.elapsed / 1000.0 / 1000.0 / 1000.0
          end
          elapsed_times.inject(:+) / elapsed_times.size
        end
      end

      class Checker
        def initialize(old_statistics,
                       new_statistics,
                       output,
                       threshold,
                       target_queries)
          @old_statistics = old_statistics
          @new_statistics = new_statistics
          @output = output
          @threshold = threshold
          @target_queries = target_queries
        end

        def check
          old_statistics = filter_statistics(@old_statistics)
          new_statistics = filter_statistics(@new_statistics)
          old_queries = old_statistics.group_by(&:raw_command)
          new_queries = new_statistics.group_by(&:raw_command)

          query_statistics = []
          old_queries.each_key do |query|
            query_statistic = QueryStatistic.new(query,
                                                 old_queries[query],
                                                 new_queries[query],
                                                 @threshold)
            next unless query_statistic.slow?
            query_statistics << query_statistic
          end

          n_slow_queries = 0
          n_target_operations = 0
          n_slow_operations = 0
          query_statistics.sort_by(&:ratio).each do |query_statistic|
            n_slow_queries += 1
            @output.puts(<<-REPORT)
Query: #{query_statistic.query}
  Mean (old): #{format_elapsed_time(query_statistic.old_elapsed_time)}
  Mean (new): #{format_elapsed_time(query_statistic.new_elapsed_time)}
  Diff:       #{format_diff(query_statistic)}
            REPORT
            next unless query_statistic.same_operations?

            @output.puts(<<-REPORT)
  Operations:
            REPORT
            query_statistic.each_operation_statistic do |operation_statistic|
              n_target_operations += 1
              next unless operation_statistic.slow?

              n_slow_operations += 1
              index = operation_statistic.index
              name = operation_statistic.name
              context = operation_statistic.context
              label = [name, context].compact.join(" ")
              old_elapsed_time = operation_statistic.old_elapsed_time
              new_elapsed_time = operation_statistic.new_elapsed_time
              @output.puts(<<-REPORT)
    Operation[#{index}]: #{label}
      Mean (old): #{format_elapsed_time(old_elapsed_time)}
      Mean (new): #{format_elapsed_time(new_elapsed_time)}
      Diff:       #{format_diff(operation_statistic)}
              REPORT
            end
          end

          n_all_queries = @old_statistics.size
          n_target_queries = old_queries.size
          n_old_cached_queries = count_cached_queries(@old_statistics)
          n_new_cached_queries = count_cached_queries(@new_statistics)
          @output.puts(<<-REPORT)
Summary:
  Slow queries:    #{format_summary(n_slow_queries, n_target_queries)}
  Slow operations: #{format_summary(n_slow_operations, n_target_operations)}
  Caches (old):    #{format_summary(n_old_cached_queries, n_all_queries)}
  Caches (new):    #{format_summary(n_new_cached_queries, n_all_queries)}
          REPORT
          true
        end

        private
        def count_cached_queries(statistics)
          n_cached_queries = 0
          statistics.each do |statistic|
            n_cached_queries += 1 if statistic.cache_used?
          end
          n_cached_queries
        end

        def filter_statistics(statistics)
          statistics.find_all do |statistic|
            target_statistic?(statistic)
          end
        end

        def target_statistic?(statistic)
          return false if statistic.cache_used?
          return true if @target_queries.empty?
          @target_queries.include?(statistic.raw_command)
        end

        def format_elapsed_time(elapsed_time)
          if elapsed_time < (1 / 1000.0 / 1000.0)
            "%.1fnsec" % (elapsed_time * 1000 * 1000)
          elsif elapsed_time < (1 / 1000.0)
            "%.1fusec" % (elapsed_time * 1000 * 1000)
          elsif elapsed_time < 1
            "%.1fmsec" % (elapsed_time * 1000)
          elsif elapsed_time < 60
            "%.1fsec" % elapsed_time
          else
            "%.1fmin" % (elapsed_time / 60)
          end
        end

        def format_diff(statistic)
          "%s%s/%+.2f" % [
            statistic.diff_elapsed_time < 0 ? "-" : "+",
            format_elapsed_time(statistic.diff_elapsed_time),
            statistic.ratio,
          ]
        end

        def format_summary(n_slows, total)
          if total.zero?
            percentage = 0.0
          else
            percentage = (n_slows / total.to_f) * 100
          end
          "%d/%d(%6.2f%%)" % [n_slows, total, percentage]
        end
      end
    end
  end
end
