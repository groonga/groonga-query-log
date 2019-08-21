# Copyright (C) 2014-2018  Kouhei Sutou <kou@clear-code.com>
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

module GroongaQueryLog
  class ResponseComparer
    def initialize(command, response1, response2, options={})
      @command = command
      @response1 = response1
      @response2 = response2
      @options = options.dup
      @options[:care_order] = true if @options[:care_order].nil?
      @options[:ignored_drilldown_keys] ||= []
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
        when "status"
          same_cache_hit_rate?
        else
          same_response?
        end
      end
    end

    private
    def error_response?(response)
      response.is_a?(Groonga::Client::Response::Error)
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
          return false unless same_records_all_output_columns?
        elsif have_unary_minus_output_column?
          return false unless same_records_unary_minus_output_column?
        else
          return false unless same_records?
        end
        same_drilldowns?
      else
        same_size_response?
      end
    end

    def same_cache_hit_rate?
      cache_hit_rate1 = @response1.body["cache_hit_rate"]
      cache_hit_rate2 = @response2.body["cache_hit_rate"]
      (cache_hit_rate1 - cache_hit_rate2).abs < (10 ** -13)
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
      sort_items = @command.sort_keys
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

      columns1 = normalize_columns(records_result1[1])
      columns2 = normalize_columns(records_result2[1])
      if all_output_columns?
        columns1.sort_by(&:first) == columns2.sort_by(&:first)
      else
        columns1 == columns2
      end
    end

    def have_unary_minus_output_column?
      output_columns = @command.output_columns
      return false if output_columns.nil?
      output_columns.split(/\s*,?\s*/).any? {|column| column.start_with?("-")}
    end

    def same_records_unary_minus_output_column?
      records_result1 = @response1.body[0] || []
      records_result2 = @response2.body[0] || []
      return false if records_result1.size != records_result2.size

      n_hits1 = records_result1[0]
      n_hits2 = records_result2[0]
      return false if n_hits1 != n_hits2

      columns1 = normalize_columns(records_result1[1])
      columns2 = normalize_columns(records_result2[1])
      records1 = records_result1[2..-1]
      records2 = records_result2[2..-1]

      if columns1.size != columns2.size
        if columns2.size > columns1.size
          columns1, columns2 = columns2, columns1
          records1, records2 = records2, records1
        end
      end

      records1.each_with_index do |record1, record_index|
        record2 = records2[record_index]
        column_offset2 = 0
        columns1.each_with_index do |name, column_index1|
          column_index2 = column_offset2 + column_index1
          if name != columns2[column_index2]
            column_offset2 -= 1
            next
          end
          value1 = record1[column_index1]
          value1 = normalize_value(value1, columns1[column_index1])
          value2 = record2[column_index2]
          value2 = normalize_value(value2, columns2[column_index2])
          return false if value1 != value2
        end
      end

      true
    end

    def all_output_columns?
      output_columns = @command.output_columns
      output_columns.nil? or
        /\A\s*\z/ === output_columns or
        output_columns.split(/\s*,?\s*/).include?("*")
    end

    def same_records_all_output_columns?
      records_result1 = @response1.body[0] || []
      records_result2 = @response2.body[0] || []
      return false if records_result1.size != records_result2.size

      n_hits1 = records_result1[0]
      n_hits2 = records_result2[0]
      return false if n_hits1 != n_hits2

      columns1 = normalize_columns(records_result1[1])
      columns2 = normalize_columns(records_result2[1])
      return false if columns1.sort_by(&:first) != columns2.sort_by(&:first)

      column_to_index1 = make_column_to_index_map(columns1)
      column_to_index2 = make_column_to_index_map(columns2)

      records1 = records_result1[2..-1]
      records2 = records_result2[2..-1]
      sort_keys = @command.sort_keys
      if @command.respond_to?(:shard_key)
        shard_key = @command.shard_key
        sort_keys.unshift(shard_key)
      end
      unless sort_keys.empty?
        records1 = sort_records(records1, columns1, sort_keys)
        records2 = sort_records(records2, columns2, sort_keys)
      end
      records1.each_with_index do |record1, record_index|
        record2 = records2[record_index]
        column_to_index1.each do |name, column_index1|
          value1 = record1[column_index1]
          value1 = normalize_value(value1, columns1[column_index1])
          column_index2 = column_to_index2[name]
          value2 = record2[column_index2]
          value2 = normalize_value(value2, columns2[column_index2])
          return false if value1 != value2
        end
      end

      true
    end

    def same_records?
      record_set1 = @response1.body[0] || []
      record_set2 = @response2.body[0] || []
      same_record_set?(record_set1,
                       record_set2)
    end

    def same_record_set?(record_set1, record_set2)
      return false if record_set1.size != record_set2.size

      n_hits1 = record_set1[0]
      n_hits2 = record_set2[0]
      return false if n_hits1 != n_hits2

      columns1 = normalize_columns(record_set1[1])
      columns2 = normalize_columns(record_set2[1])
      return false if columns1 != columns2

      records1 = record_set1[2..-1]
      records2 = record_set2[2..-1]
      records1.each_with_index do |record1, record_index|
        record2 = records2[record_index]
        columns1.each_with_index do |column1, column_index|
          value1 = record1[column_index]
          value1 = normalize_value(value1, column1)
          value2 = record2[column_index]
          value2 = normalize_value(value2, column1)
          return false if value1 != value2
        end
      end

      true
    end

    def sort_records(records, columns, sort_keys)
      indexed_columns = columns.collect.with_index.to_a
      sorted_indexed_columns = indexed_columns.sort_by do |(name, type), i|
        [sort_keys.index(name) || columns.size, name]
      end
      records.sort_by do |record|
        sorted_indexed_columns.collect do |column, i|
          normalize_value(record[i], column)
        end
      end
    end

    def make_column_to_index_map(columns)
      map = {}
      columns.each_with_index do |(name, _), i|
        map[name] = i
      end
      map
    end

    def same_drilldowns?
      drilldowns1 = @response1.body[1..-1] || []
      drilldowns2 = @response2.body[1..-1] || []
      return false if drilldowns1.size != drilldowns2.size
      drilldown_classes1 = drilldowns1.collect(&:class)
      drilldown_classes2 = drilldowns2.collect(&:class)
      return false if drilldown_classes1 != drilldown_classes2

      ignored_drilldown_keys = @options[:ignored_drilldown_keys]

      if drilldown_classes1 == [Hash]
        drilldowns1 = drilldowns1[0]
        drilldowns2 = drilldowns2[0]
        drilldowns1.each do |drilldown_label, drilldown1|
          next if ignored_drilldown_keys.include?(drilldown_label)
          drilldown2 = drilldowns2[drilldown_label]
          return false unless same_record_set?(drilldown1, drilldown2)
        end
      else
        drilldown_keys = @command.drilldowns
        drilldowns1.each_with_index do |drilldown1, drilldown_index|
          drilldown_key = drilldown_keys[drilldown_index]
          next if ignored_drilldown_keys.include?(drilldown_key)
          drilldown2 = drilldowns2[drilldown_index]
          return false unless same_record_set?(drilldown1, drilldown2)
        end
      end

      true
    end

    def normalize_columns(columns)
      columns.collect do |name, type|
        type = nil if type == "null"
        [name, type]
      end
    end

    def normalize_value(value, column)
      type = column[1]
      case type
      when "Float"
        value.round(10)
      else
        value
      end
    end
  end
end
