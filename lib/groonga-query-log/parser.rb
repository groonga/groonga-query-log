# Copyright (C) 2011-2018  Kouhei Sutou <kou@clear-code.com>
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

require "groonga-query-log/statistic"

module GroongaQueryLog
  class Parser
    PATTERN =
      /\A(?<year>\d{4})-(?<month>\d\d)-(?<day>\d\d)
         \ (?<hour>\d\d):(?<minute>\d\d):(?<second>\d\d)\.(?<microsecond>\d+)
         \|(?<context_id>.+?)
         \|(?<type>[>:<])/x

    class << self
      def target_line?(line)
        if line.respond_to?(:valid_encoding?)
          return false unless line.valid_encoding?
        end

        return false unless PATTERN.match(line)

        true
      end
    end

    attr_reader :current_path
    def initialize(options={})
      @options = options
      @slow_operation_threshold = options[:slow_operation_threshold]
      @slow_response_threshold = options[:slow_response_threshold]
      @target_commands = options[:target_commands]
      @target_tables = options[:target_tables]
      @parsing_statistics = {}

      @current_path = nil
    end

    # Parses query-log file as stream to
    # {GroongaQueryLog::Analyzer::Statistic}s including some
    # informations for each query.
    #
    # @param [IO] input IO for input query log file.
    # @yield [statistics] if a block is specified, it is called
    #   every time a query is finished parsing.
    # @yieldparam [GroongaQueryLog::Statistic] statistic
    #   statistics of each query in log files.
    def parse(input, &block)
      return to_enum(__method__, input) unless block_given?

      input.each_line do |line|
        next unless line.valid_encoding?

        match_data = PATTERN.match(line)
        next if match_data.nil?

        year = Integer(match_data[:year], 10)
        month = Integer(match_data[:month], 10)
        day = Integer(match_data[:day], 10)
        hour = Integer(match_data[:hour], 10)
        minute = Integer(match_data[:minute], 10)
        second = Integer(match_data[:second], 10)
        microsecond = Integer(match_data[:microsecond], 10)
        context_id = match_data[:context_id]
        type = match_data[:type]
        rest = match_data.post_match.strip
        time_stamp = Time.local(year,
                                month,
                                day,
                                hour,
                                minute,
                                second,
                                microsecond)
        parse_line(time_stamp, context_id, type, rest, &block)
      end
    end

    def parse_paths(paths, &block)
      return to_enum(__method__, paths) unless block_given?

      target_paths = GroongaLog::Parser.sort_paths(paths)
      target_paths.each do |path|
        GroongaLog::Input.open(path) do |log|
          @current_path = path
          begin
            parse(log, &block)
          ensure
            @current_path = nil
          end
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
        return if rest.empty?
        statistic = create_statistic(context_id)
        statistic.start(time_stamp, rest)
        @parsing_statistics[context_id] = statistic
      when ":"
        return unless /\A
                       (?<elapsed>\d+)
                       \ 
                       (?<raw_message>
                         (?<name>[a-zA-Z._-]+)
                         (?<sub_name_before>\[.+?\])?
                         (?:\((?<n_records>\d+)\))?
                         (?<sub_name_after>\[.+?\])?
                         (?::\ (?<extra>.*))?
                       )
                      /x =~ rest
        statistic = @parsing_statistics[context_id]
        return if statistic.nil?
        full_name = "#{name}#{sub_name_before}#{sub_name_after}"
        statistic.add_operation(:name => full_name,
                                :elapsed => elapsed.to_i,
                                :n_records => n_records.to_i,
                                :extra => extra,
                                :raw_message => raw_message)
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
      statistic = Statistic.new(context_id)
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
