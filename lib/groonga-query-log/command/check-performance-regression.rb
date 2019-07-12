# Copyright (C) 2019 Kentaro Hayashi <hayashi@clear-code.com>
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
require "groonga-query-log/command-line"

require "groonga-query-log/command/analyzer"
require "groonga-query-log/command/analyzer/sized-statistics"

module GroongaQueryLog
  module Command
    class CheckPerformanceRegression < CommandLine
      CACHED_QUERY_OPERAION_COUNT = 1
      NSEC_IN_SECONDS = (1000 * 1000 * 1000.0)

      def initialize(options={})
        setup_options
        @output = options[:output] || $stdout
        @n_processed_queries = 0
        @n_slow_response = 0
        @n_slow_operation = 0
        @n_processed_operations = 0
        @n_cached_queries = 0
        @target_queries = []
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

        paths.each_with_index do |path, index|
          if File.directory?(path)
            if index == 0
              @options[:input_old_query] = Dir.glob("#{path}/*.log")
            else
              @options[:input_new_query] = Dir.glob("#{path}/*.log")
            end
          elsif File.exist?(path)
            if index == 0
              @options[:input_old_query] = [path]
            else
              @options[:input_new_query] = [path]
            end
          else
            $stderr.puts("query log path doesn't exist: <#{path}>")
            return false
          end
        end

        if @options[:output].is_a?(String)
          if @options[:output] == "-"
            @output = $stdin
          else
            @output = File.open(@options[:output], "w")
          end
        end

        old_statistics = analyze(@options[:input_old_query])
        new_statistics = analyze(@options[:input_new_query])

        old_queries, new_queries = group_statistics(old_statistics, new_statistics)

        statistics = []
        old_queries.each_key do |query|
          old_elapsed_nsec = average_elapsed_nsec(old_queries[query])
          new_elapsed_nsec = average_elapsed_nsec(new_queries[query])
          percentage = elapsed_percentage(old_elapsed_nsec, new_elapsed_nsec, @options[:slow_response_threshold])
          statistics << {
            :query => query,
            :percentage => percentage,
            :old_elapsed_nsec => old_elapsed_nsec,
            :new_elapsed_nsec => new_elapsed_nsec
          }
        end

        statistics = statistics.sort_by { |statistic| statistic[:percentage] }

        @n_processed_queries = old_queries.keys.count

        statistics.each do |statistic|
          query = statistic[:query]
          old_elapsed_nsec = statistic[:old_elapsed_nsec]
          new_elapsed_nsec = statistic[:new_elapsed_nsec]

          if slow_response?(old_elapsed_nsec, new_elapsed_nsec)
            @n_slow_response += 1
            @output.puts("Query: #{query}")
            percentage = statistic[:percentage]
            @output.puts("  Before(average): #{old_elapsed_nsec} (nsec)")
            @output.puts("   After(average): #{new_elapsed_nsec} (nsec)")
            @output.puts("          Changes: #{format_elapsed_calculated_percentage(percentage, old_elapsed_nsec, new_elapsed_nsec)}")
            @output.puts("       Operations:")
            old_operation_nsecs = average_elapsed_operation_nsecs(old_queries[query])
            new_operation_nsecs = average_elapsed_operation_nsecs(new_queries[query])
            old_operation_nsecs.each_with_index do |operation, index|
              new_operation = new_operation_nsecs[index]
              @n_processed_operations += 1
              if slow_operation?(operation[:elapsed], new_operation[:elapsed])
                @n_slow_operation += 1
                @output.puts("%24s[%d]: %s" % [
                               "Operation",
                               index,
                               operation[:name]
                             ])
                @output.puts("%24s[%d]: %s (nsec)" % [
                               "Before(average)", index,
                               operation[:elapsed]
                             ])
                @output.puts("%24s[%d]: %s (nsec)" % [
                               "After(average)", index,
                               new_operation[:elapsed]
                             ])
                @output.puts("%24s[%d]: %s" % [
                               "Changes", index,
                               format_elapsed_percentage(operation[:elapsed],
                                                         new_operation[:elapsed], @options[:slow_operation_threshold])
                             ])
                @output.puts("%24s[%d]: %s" % [
                               "Context", index, operation[:context]
                             ])
              end
            end
          end
        end

        @output.puts("Summary: slow response: %d/%d(%.2f%%) slow operation: %d/%d(%.2f%%) cached: %d" % [
                       @n_slow_response, @n_processed_queries,
                       @n_slow_response / @n_processed_queries.to_f * 100,
                       @n_slow_operation, @n_processed_operations,
                       @n_slow_operation / @n_processed_operations.to_f * 100,
                       @n_cached_queries,
                     ])

        if @output.kind_of?(File)
          @output.close
        end

        true
      end

      private
      def elapsed_percentage(old_elapsed_nsec, new_elapsed_nsec, threshold)
        if old_elapsed_nsec.zero?
          if new_elapsed_nsec.zero?
          0.0
          elsif (new_elapsed_nsec / NSEC_IN_SECONDS) < threshold
            -Float::INFINITY
          else
            Float::INFINITY
          end
        else
          (new_elapsed_nsec / old_elapsed_nsec) * 100 - 100
        end
      end

      def average_elapsed_nsec(statistics)
        elapsed_times = statistics.collect do |statistic|
          statistic.elapsed
        end
        elapsed_times.inject(:+).to_f / elapsed_times.size
      end

      def average_elapsed_operation_nsecs(statistics)
        operations = []
        statistics.first.operations.each_with_index do |operation, index|
          elapsed_times = statistics.collect do |statistic|
            statistic.operations[index][:relative_elapsed]
          end
          operations << {
            :name => operation[:name],
            :elapsed => elapsed_times.inject(:+).to_f / elapsed_times.size,
            :context => operation[:context]
          }
        end
        operations
      end

      def slow_response?(old_elapsed_nsec, new_elapsed_nsec)
        return false if old_elapsed_nsec == new_elapsed_nsec
        ratio = elapsed_percentage(old_elapsed_nsec, new_elapsed_nsec, @options[:slow_response_threshold])
        elapsed_sec = ((new_elapsed_nsec - old_elapsed_nsec) / NSEC_IN_SECONDS)
        (ratio >= @options[:slow_response_ratio]) and
          (elapsed_sec >= @options[:slow_response_threshold])
      end

      def slow_operation?(old_elapsed_nsec, new_elapsed_nsec)
        return false if old_elapsed_nsec == new_elapsed_nsec
        ratio = elapsed_percentage(old_elapsed_nsec, new_elapsed_nsec, @options[:slow_operation_threshold])
        elapsed_sec = ((new_elapsed_nsec - old_elapsed_nsec) / NSEC_IN_SECONDS)
        slow_operation = ((ratio >= @options[:slow_operation_ratio]) and
                         (elapsed_sec >= @options[:slow_operation_threshold]))
        slow_operation
      end

      def format_elapsed_calculated_percentage(percentage, old_elapsed_nsec, new_elapsed_nsec)
        flag = percentage > 0 ? "+" : ""
        "(%s%.2f%% %s%.2fsec/%s%.2fmsec/%s%.2fusec/%s%.2fnsec)" % [
          flag,
          percentage,
          flag, (new_elapsed_nsec - old_elapsed_nsec) / 1000 / 1000 / 1000,
          flag, (new_elapsed_nsec - old_elapsed_nsec) / 1000 / 1000,
          flag, (new_elapsed_nsec - old_elapsed_nsec) / 1000,
          flag, new_elapsed_nsec - old_elapsed_nsec,
        ]
      end

      def format_elapsed_percentage(old_elapsed_nsec, new_elapsed_nsec, threshold)
        percentage = elapsed_percentage(old_elapsed_nsec, new_elapsed_nsec, threshold)
        format_elapsed_calculated_percentage(percentage, old_elapsed_nsec, new_elapsed_nsec)
      end

      def cached_query?(statistics)
        statistics.operations.collect { |operation| operation[:name] } == ["cache"]
      end

      def different_query?(old_statistics, new_statistics)
        old_statistics.raw_command != new_statistics.raw_command
      end

      def setup_options
        @options = {}
        @options[:n_entries] = 1000
        @options[:order] = "start-time"
        @options[:slow_operation_ratio] = 10
        @options[:slow_response_ratio] = 0
        @options[:slow_operation_threshold] = 0.1
        @options[:slow_response_threshold] = 0.2
        @options[:input_old_query] = nil
        @options[:input_new_query] = nil

        @option_parser = OptionParser.new do |parser|
          parser.version = VERSION
          parser.banner += " OLD_QUERY_LOG NEW_QUERY_LOG"

          parser.on("-n", "--n-entries=N",
                    Integer,
                    "Analyze N query log entries",
                    "(#{@options[:n_entries]})") do |n|
            @options[:n_entries] = n
          end

          parser.on("--output=PATH",
                    "Output to PATH.",
                    "(#{@options[:output]})") do |output|
            @options[:output] = output
          end

          parser.on("--target-query-file=TARGET_QUERY_FILE",
                    "Analyze matched queries which are listed in specified TARGET_QUERY_FILE.",
                    "(#{@options[:target_queries]})") do |path|
            if File.exist?(path)
              @target_queries = File.readlines(path, chomp: true)
            else
              raise OptionParser::InvalidOption.new("target query file doesn't exist: <#{path}>")
            end
          end

          parser.on("--slow-operation-ratio=PERCENTAGE",
                    Float,
                    "Use PERCENTAGE% as threshold to detect slow operations.",
                    "Example: --slow-operation-ratio=#{@options[:slow_operation_ratio]} means",
                    "changed amount of operation time is #{@options[:slow_operation_ratio]}% or more.",
                    "(#{@options[:slow_operation_ratio]})") do |ratio|
            @options[:slow_operation_ratio] = ratio
          end

          parser.on("--slow-response-ratio=PERCENTAGE",
                    Float,
                    "Use PERCENTAGE% as threshold to detect slow responses.",
                    "Example: --slow-response-ratio=#{@options[:slow_response_ratio]} means",
                    "changed amount of response time is #{@options[:slow_response_ratio]}% or more.",
                    "(#{@options[:slow_response_ratio]})") do |ratio|
            @options[:slow_response_ratio] = ratio
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
        end
      end

      def group_statistics(old_statistics, new_statistics)
        old_queries = {}
        new_queries = {}
        old_statistics.zip(new_statistics) do |old_statistic, new_statistic|
          if cached_query?(old_statistic)
            @n_cached_queries += 1
            next
          end
          next if different_query?(old_statistic, new_statistic)

          raw_command = old_statistic.raw_command
          next unless target_query?(raw_command)

          if old_queries[raw_command]
            statistics = old_queries[raw_command]
            statistics << old_statistic
          else
            old_queries[raw_command] ||= []
            old_queries[raw_command] << old_statistic
          end

          if new_queries[raw_command]
            statistics = new_queries[raw_command]
            statistics << new_statistic
          else
            new_queries[raw_command] ||= []
            new_queries[raw_command] << new_statistic
          end
        end
        [old_queries, new_queries]
      end

      def target_query?(query)
        return true unless @options[:target_query_file]
        @options[:target_queries].include?(query)
      end


      def analyze(log_paths)
        statistics = GroongaQueryLog::Command::Analyzer::SizedStatistics.new
        statistics.apply_options(@options)
        full_statistics = []

        begin
          n = 1
          parse(log_paths) do |statistic|
            next if n > @options[:n_entries]
            full_statistics << statistic
            n = n + 1
          end
        rescue Error
          $stderr.puts($!.message)
          return false
        end

        full_statistics
      end

      def parse(log_paths, &process_statistic)
        parser = Parser.new(@options)
        parse_log(parser, log_paths, &process_statistic)
      end
    end
  end
end
