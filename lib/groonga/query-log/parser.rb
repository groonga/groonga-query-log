# Copyright (C) 2011-2016  Kouhei Sutou <kou@clear-code.com>
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

require "groonga/query-log/analyzer/statistic"

module Groonga
  module QueryLog
    class Parser
      def initialize(options={})
        @options = options
        @slow_operation_threshold = options[:slow_operation_threshold]
        @slow_response_threshold = options[:slow_response_threshold]
        @target_commands = options[:target_commands]
        @target_tables = options[:target_tables]
        @parsing_statistics = {}
      end

      # Parses query-log file as stream to
      # {Groonga::QueryLog::Analyzer::Statistics} including some
      # informations for each query.
      #
      # @param [IO] input IO for input query log file.
      # @yield [statistics] if a block is specified, it is called
      #   every time a query is finished parsing.
      # @yieldparam [Groonga::QueryLog::Analyzer::Statistic] statistic
      #   statistics of each query in log files.
      def parse(input, &block)
        input.each_line do |line|
          next unless line.valid_encoding?
          case line
          when /\A(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)\.(\d+)\|(.+?)\|([>:<])/
            year, month, day, hour, minutes, seconds, micro_seconds =
              $1, $2, $3, $4, $5, $6, $7
            context_id = $8
            type = $9
            rest = $POSTMATCH.strip
            time_stamp = Time.local(year, month, day, hour, minutes, seconds,
                                    micro_seconds)
            parse_line(time_stamp, context_id, type, rest, &block)
          end
        end
      end

      def parsing_statistics
        @parsing_statistics.values
      end

      private
      def parse_line(time_stamp, context_id, type, rest, &block)
        case type
        when ">"
          statistic = create_statistic(context_id)
          statistic.start(time_stamp, rest)
          @parsing_statistics[context_id] = statistic
        when ":"
          return unless /\A(\d+) (.+)\((\d+)\)/ =~ rest
          elapsed = $1
          name = $2
          n_records = $3.to_i
          statistic = @parsing_statistics[context_id]
          return if statistic.nil?
          statistic.add_operation(:name => name,
                                  :elapsed => elapsed.to_i,
                                  :n_records => n_records)
        when "<"
          return unless /\A(\d+) rc=(-?\d+)/ =~ rest
          elapsed = $1
          return_code = $2
          statistic = @parsing_statistics.delete(context_id)
          return if statistic.nil?
          statistic.finish(elapsed.to_i, return_code.to_i)
          return unless target_statistic?(statistic)
          block.call(statistic)
        end
      end

      def create_statistic(context_id)
        statistic = Analyzer::Statistic.new(context_id)
        if @slow_operation_threshold
          statistic.slow_operation_threshold = @slow_operation_threshold
        end
        if @slow_response_threshold
          statistic.slow_response_threshold = @slow_response_threshold
        end
        statistic
      end

      def target_statistic?(statistic)
        if @target_commands
          unless @target_commands.include?(statistic.command.name)
            return false
          end
        end

        if @target_tables
          table = statistic.command["table"]
          return false if table.nil?

          unless @target_tables.include?(table)
            return false
          end
        end

        true
      end
    end
  end
end
