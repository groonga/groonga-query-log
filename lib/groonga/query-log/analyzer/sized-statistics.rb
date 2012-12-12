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

require "groonga/query-log/analyzer/sized-grouped-operations"
require "groonga/query-log/analyzer/reporter/console"
require "groonga/query-log/analyzer/reporter/html"
require "groonga/query-log/analyzer/reporter/json"

module Groonga
  module QueryLog
    class Analyzer
    class SizedStatistics < Array
      attr_reader :n_responses, :n_slow_responses, :n_slow_operations
      attr_reader :slow_operations, :total_elapsed
      attr_reader :start_time, :last_time
      attr_accessor :slow_operation_threshold, :slow_response_threshold
      def initialize
        @max_size = 10
        self.order = "-elapsed"
        @slow_operation_threshold = 0.1
        @slow_response_threshold = 0.2
        @start_time = nil
        @last_time = nil
        @n_responses = 0
        @n_slow_responses = 0
        @n_slow_operations = 0
        @slow_operations = SizedGroupedOperations.new
        @total_elapsed = 0
        @collect_slow_statistics = true
      end

      def order=(new_order)
        @order = new_order
        @sorter = create_sorter
      end

      def apply_options(options)
        @max_size = options[:n_entries] || @max_size
        self.order = options[:order] || @order
        @slow_operation_threshold =
          options[:slow_operation_threshold] || @slow_operation_threshold
        @slow_response_threshold =
          options[:slow_response_threshold] || @slow_response_threshold
        unless options[:report_summary].nil?
          @collect_slow_statistics = options[:report_summary]
        end
        @slow_operations.apply_options(options)
      end

      def <<(statistic)
        update_statistic(statistic)
        if size < @max_size
          super(statistic)
          replace(self)
        else
          if @sorter.call(statistic) < @sorter.call(last)
            super(statistic)
            replace(self)
          end
        end
        self
      end

      def replace(other)
        sorted_other = other.sort_by(&@sorter)
        if sorted_other.size > @max_size
          super(sorted_other[0, @max_size])
        else
          super(sorted_other)
        end
      end

      def responses_per_second
        _period = period
        if _period.zero?
          0
        else
          @n_responses.to_f / _period
        end
      end

      def slow_response_ratio
        if @n_responses.zero?
          0
        else
          (@n_slow_responses.to_f / @n_responses) * 100
        end
      end

      def period
        if @start_time and @last_time
          @last_time - @start_time
        else
          0
        end
      end

      def each_slow_operation
        @slow_operations.each do |grouped_operation|
          total_elapsed = grouped_operation[:total_elapsed]
          n_operations = grouped_operation[:n_operations]
          ratios = {
            :total_elapsed_ratio => total_elapsed / @total_elapsed * 100,
            :n_operations_ratio => n_operations / @n_slow_operations.to_f * 100,
          }
          yield(grouped_operation.merge(ratios))
        end
      end

      private
      def create_sorter
        case @order
        when "-elapsed"
          lambda do |statistic|
            -statistic.elapsed
          end
        when "elapsed"
          lambda do |statistic|
            statistic.elapsed
          end
        when "-start-time"
          lambda do |statistic|
            -statistic.start_time
          end
        else
          lambda do |statistic|
            statistic.start_time
          end
        end
      end

      def update_statistic(statistic)
        statistic.slow_response_threshold = @slow_response_threshold
        statistic.slow_operation_threshold = @slow_operation_threshold
        @start_time ||= statistic.start_time
        @start_time = [@start_time, statistic.start_time].min
        @last_time ||= statistic.last_time
        @last_time = [@last_time, statistic.last_time].max
        @n_responses += 1
        @total_elapsed += statistic.elapsed_in_seconds
        return unless @collect_slow_statistics
        if statistic.slow?
          @n_slow_responses += 1
          if statistic.select_command?
            statistic.each_operation do |operation|
              next unless operation[:slow?]
              @n_slow_operations += 1
              @slow_operations << operation
            end
          end
        end
      end
    end
    end
  end
end
