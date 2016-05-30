# Copyright (C) 2014-2015  Kouhei Sutou <kou@clear-code.com>
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

module Groonga
  module QueryLog
    class ResponseComparer
      def initialize(command, response1, response2, options={})
        @command = command
        @response1 = response1
        @response2 = response2
        @options = options
        @options[:care_order] = true if @options[:care_order].nil?
      end

      def same?
        if error_response?(@response1) or error_response?(@response2)
          if error_response?(@response1) and error_response?(@response2)
            same_error_response?
          else
            false
          end
        else
          case @command.name
          when "select", "logical_select"
            same_select_response?
          else
            same_response?
          end
        end
      end

      private
      def error_response?(response)
        response.is_a?(Client::Response::Error)
      end

      def same_error_response?
        return_code1 = @response1.header[0]
        return_code2 = @response2.header[0]
        return_code1 == return_code2
      end

      def same_response?
        @response1.body == @response2.body
      end

      def same_select_response?
        if care_order?
          if all_output_columns?
            same_all_output_columns?
          else
            same_response?
          end
        else
          same_size_response?
        end
      end

      def care_order?
        return false unless @options[:care_order]
        return false if random_sort?

        true
      end

      def random_score?
        return false unless @command.respond_to?(:scorer)
        /\A_score\s*=\s*rand\(\)\z/ === @command.scorer
      end

      def random_sort?
        random_score? and score_sort?
      end

      def score_sort?
        sort_items = (@command.sortby || "").split(/\s*,\s*/)
        normalized_sort_items = sort_items.collect do |item|
          item.gsub(/\A[+-]/, "")
        end
        normalized_sort_items.include?("_score")
      end

      def same_size_response?
        records_result1 = @response1.body[0] || []
        records_result2 = @response2.body[0] || []
        return false if records_result1.size != records_result2.size

        n_hits1 = records_result1[0]
        n_hits2 = records_result2[0]
        return false if n_hits1 != n_hits2

        columns1 = records_result1[1]
        columns2 = records_result2[1]
        if all_output_columns?
          columns1.sort_by(&:first) == columns2.sort_by(&:first)
        else
          columns1 == columns2
        end
      end

      def all_output_columns?
        output_columns = @command.output_columns
        output_columns.nil? or
          /\A\s*\z/ === output_columns or
          output_columns.split(/\s*,?\s*/).include?("*")
      end

      def same_all_output_columns?
        records_result1 = @response1.body[0] || []
        records_result2 = @response2.body[0] || []
        return false if records_result1.size != records_result2.size

        n_hits1 = records_result1[0]
        n_hits2 = records_result2[0]
        return false if n_hits1 != n_hits2

        columns1 = records_result1[1]
        columns2 = records_result2[1]
        return false if columns1.sort_by(&:first) != columns2.sort_by(&:first)

        column_to_index1 = make_column_to_index_map(columns1)
        column_to_index2 = make_column_to_index_map(columns2)

        records1 = records_result1[2..-1]
        records2 = records_result2[2..-1]
        records1.each_with_index do |record1, record_index|
          record2 = records2[record_index]
          column_to_index1.each do |name, column_index1|
            value1 = record1[column_index1]
            value2 = record2[column_to_index2[name]]
            return false if value1 != value2
          end
        end

        true
      end

      def make_column_to_index_map(columns)
        map = {}
        columns.each_with_index do |(name, _), i|
          map[name] = i
        end
        map
      end
    end
  end
end
