# Copyright (C) 2014-2018  Kouhei Sutou <kou@clear-code.com>
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
        when "logical_range_filter"
          same_range_filter_response?
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

    def same_range_filter_response?
      if all_output_columns?
        same_records_all_output_columns?
      elsif have_unary_minus_output_column?
        same_records_unary_minus_output_column?
      else
        same_records?
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
      records1 = @response1.raw_records
      records2 = @response2.raw_records
      return false if records1.size != records2.size

      if @response1.respond_to?(:n_hits)
        n_hits1 = @response1.n_hits
        n_hits2 = @response2.n_hits
        return false if n_hits1 != n_hits2
      end

      columns1 = normalize_columns(@response1.raw_columns)
      columns2 = normalize_columns(@response2.raw_columns)
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
      records1 = @response1.raw_records
      records2 = @response2.raw_records
      return false if records1.size != records2.size

      if @response1.respond_to?(:n_hits)
        n_hits1 = @response1.n_hits
        n_hits2 = @response2.n_hits
        return false if n_hits1 != n_hits2
      end

      columns1 = normalize_columns(@response1.raw_columns)
      columns2 = normalize_columns(@response2.raw_columns)

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
      records1 = @response1.raw_records
      records2 = @response2.raw_records
      return false if records1.size != records2.size

      if @response1.respond_to?(:n_hits)
        n_hits1 = @response1.n_hits
        n_hits2 = @response2.n_hits
        return false if n_hits1 != n_hits2
      end

      columns1 = normalize_columns(@response1.raw_columns)
      columns2 = normalize_columns(@response2.raw_columns)
      return false if columns1.sort_by(&:first) != columns2.sort_by(&:first)

      column_to_index1 = make_column_to_index_map(columns1)
      column_to_index2 = make_column_to_index_map(columns2)

      sort_keys = @command.sort_keys
      if @command.respond_to?(:shard_key)
        shard_key = @command.shard_key
        sort_keys.unshift(shard_key)
      end
      if need_loose_sort?(records1, columns1, records2, columns2, sort_keys)
        records1 = sort_records_loose(records1, columns1, sort_keys)
        records2 = sort_records_loose(records2, columns2, sort_keys)
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
      same_record_set?(@response1, @response2)
    end

    def same_record_set?(record_set1, record_set2)
      records1 = record_set1.raw_records
      records2 = record_set2.raw_records
      return false if records1.size != records2.size

      if record_set1.respond_to?(:n_hits)
        n_hits1 = record_set1.n_hits
        n_hits2 = record_set2.n_hits
        return false if n_hits1 != n_hits2
      end

      columns1 = normalize_columns(record_set1.raw_columns)
      columns2 = normalize_columns(record_set2.raw_columns)
      return false if columns1 != columns2

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

    def need_loose_sort?(records1, columns1, records2, columns2, sort_keys)
      return false if sort_keys.empty?
      return false unless sorted?(records1, columns1, sort_keys)
      return false unless sorted?(records2, columns2, sort_keys)
      true
    end

    def compare_records(record1, record2, columns, sort_targets)
      sort_targets.each do |i, order|
        value1 = normalize_value(record1[i], columns[i])
        value2 = normalize_value(record2[i], columns[i])
        compared = (value1 <=> value2)
        compared = -compared if order == :descendant
        return compared unless compared == 0
      end
      0
    end

    def compute_sort_targets(columns, sort_keys)
      sort_keys.collect do |sort_key|
        if sort_key.start_with?("-")
          order = :descendant
          sort_key = sort_key[1..-1]
        else
          order = :ascending
        end
        i = columns.index do |(name, _)|
          name == sort_key
        end
        next if i.nil?
        [i, order]
      end.compact
    end

    def sorted?(records, columns, sort_keys)
      sort_targets = compute_sort_targets(columns, sort_keys)
      sorted_records = records.sort do |record1, record2|
        compare_records(record1, record2, columns, sort_targets)
      end
      records == sorted_records
    end

    def sort_records_loose(records, columns, sort_keys)
      sort_targets = compute_sort_targets(columns, sort_keys)
      columns.each_with_index do |column, i|
        next if sort_targets.any? {|j, _| j == i}
        sort_targets << [i, :ascending]
      end
      records.sort do |record1, record2|
        compare_records(record1, record2, columns, sort_targets)
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
      drilldowns1 = @response1.drilldowns
      drilldowns2 = @response2.drilldowns
      return false if drilldowns1.size != drilldowns2.size

      ignored_drilldown_keys = @options[:ignored_drilldown_keys]

      if drilldowns1.is_a?(::Hash)
        drilldowns1.each do |drilldown_label, drilldown1|
          next if ignored_drilldown_keys.include?(drilldown_label)
          drilldown2 = drilldowns2[drilldown_label]
          return false unless same_record_set?(drilldown1, drilldown2)
        end
      else
        drilldowns1.zip(drilldowns2) do |drilldown1, drilldown2|
          drilldown_key = drilldown1.key
          next if ignored_drilldown_keys.include?(drilldown_key)
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
