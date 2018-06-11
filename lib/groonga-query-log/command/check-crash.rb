# Copyright (C) 2018  Kouhei Sutou <kou@clear-code.com>
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

require "groonga-query-log"
require "groonga-query-log/command-line"

module GroongaQueryLog
  module Command
    class CheckCrash < CommandLine
      def initialize
        setup_options
      end

      def run(arguments)
        begin
          log_paths = @option_parser.parse!(arguments)
        rescue OptionParser::InvalidOption => error
          $stderr.puts(error)
          return false
        end

        begin
          check(log_paths)
        rescue Interrupt
        rescue Error
          $stderr.puts($!.message)
          return false
        end

        true
      end

      private
      def setup_options
        @options = {}

        @option_parser = OptionParser.new do |parser|
          parser.version = VERSION
          parser.banner += " LOG1 ..."
        end
      end

      def open_output
        if @options[:output] == "-"
          yield($stdout)
        else
          File.open(@options[:output], "w") do |output|
            yield(output)
          end
        end
      end

      def check(log_paths)
        checker = Checker.new(log_paths)
        checker.check
      end

      class GroongaProcess
        attr_reader :pid
        attr_reader :start_time
        attr_reader :log_path
        attr_accessor :last_time
        attr_accessor :n_leaks
        attr_writer :crashed
        attr_reader :important_entries
        def initialize(pid, start_time, log_path)
          @pid = pid
          @start_time = start_time
          @last_time = @start_time
          @log_path = log_path
          @n_leaks = 0
          @crashed = false
          @important_entries = []
        end

        def crashed?
          @crashed
        end
      end

      class Checker
        def initialize(log_paths)
          split_log_paths(log_paths)
        end

        def check
          processes = ProcessEnumerator.new(@general_log_paths)
          processes.each do |process|
            if process.crashed?
              p [:crashed,
                 process.start_time.iso8601,
                 process.last_time.iso8601,
                 process.pid,
                 process.log_path]
            end

            unless process.important_entries.empty?
              puts("Important entries:")
              process.important_entries.each_with_index do |entry, i|
                puts("#{entry.timestamp.iso8601}: " +
                     "#{entry.log_level}: " +
                     "#{entry.message}")
              end
            end

            unless process.n_leaks.zero?
              p [:leak,
                 process.n_leaks,
                 process.last_time.iso8601,
                 process.log_path]
            end

            next unless process.crashed?

            start = process.start_time
            last = process.last_time
            @flushed = nil
            @unflushed_statistics = []
            query_log_parser = Parser.new
            query_log_parser.parse_paths(@query_log_paths) do |statistic|
              next if statistic.start_time < start
              break if statistic.start_time > last
              check_query_log_statistic(query_log_parser.current_path,
                                        statistic)
            end
            parsing_statistics = query_log_parser.parsing_statistics
            unless parsing_statistics.empty?
              puts("Running queries:")
              parsing_statistics.each do |statistic|
                puts("#{statistic.start_time.iso8601}:")
                puts(statistic.command.to_command_format(pretty_print: true))
              end
            end
            unless @unflushed_statistics.empty?
              puts("Unflushed commands in #{start.iso8601}/#{last.iso8601}")
              @unflushed_statistics.each do |statistic|
                puts("#{statistic.start_time.iso8601}: #{statistic.raw_command}")
              end
            end
          end
        end

        private
        def split_log_paths(log_paths)
          @general_log_paths = []
          @query_log_paths = []
          log_paths.each do |log_path|
            sample_lines = GroongaLog::Input.open(log_path) do |log_file|
              log_file.each_line.take(10)
            end
            if sample_lines.any? {|line| Parser.target_line?(line)}
              @query_log_paths << log_path
            elsif sample_lines.any? {|line| GroongaLog::Parser.target_line?(line)}
              @general_log_paths << log_path
            end
          end
        end

        def check_query_log_statistic(path, statistic)
          case statistic.command.command_name
          when "load"
            @flushed = false
            @unflushed_statistics << statistic
          when "delete"
            @flushed = false
            @unflushed_statistics << statistic
          when "io_flush"
            @flushed = true
            @unflushed_statistics.clear
          when "database_unmap"
            @unflushed_statistics.reject! do |statistic|
              statistic.command.name == "load"
            end
          when "table_list", "column_list"
            # ignore
          when /\Atable_/
            @flushed = false
            @unflushed_statistics << statistic
          when /\Acolumn_/
            @flushed = false
            @unflushed_statistics << statistic
          end
        end
      end

      class ProcessEnumerator
        def initialize(general_log_paths)
          @general_log_paths = general_log_paths
          @running_processes = {}
        end

        def each(&block)
          general_log_parser = GroongaLog::Parser.new
          general_log_parser.parse_paths(@general_log_paths) do |entry|
            check_general_log_entry(general_log_parser.current_path,
                                    entry,
                                    &block)
          end
          @running_processes.each_value do |process|
            yield(process)
          end
        end

        private
        def check_general_log_entry(path, entry, &block)
          # p [path, entry]
          case entry.log_level
          when :emergency, :alert, :critical, :error, :warning
            # p [entry.log_level, entry.message, entry.timestamp.iso8601]
          end

          case entry.message
          when /\Agrn_init:/
            process = @running_processes[entry.pid]
            if process
              process.crashed = true
              yield(process)
              @running_processes.delete(entry.pid)
            end
            process = GroongaProcess.new(entry.pid, entry.timestamp, path)
            @running_processes[entry.pid] = process
          when /\Agrn_fin \(\d+\)\z/
            n_leaks = $1.to_i
            process = @running_processes[entry.pid]
            process.n_leaks = n_leaks
            yield(process)
            @running_processes.delete(entry.pid)
          else
            @running_processes[entry.pid] ||=
              GroongaProcess.new(entry.pid, Time.at(0), path)
            process = @running_processes[entry.pid]
            case entry.log_level
            when :emergency, :alert, :critical, :error
              process.important_entries << entry
            end
            process.last_time = entry.timestamp
            case entry.message
            when "-- CRASHED!!! --"
              process.crashed = true
            when "----------------"
              if process.crashed?
                yield(process)
                @running_processes.delete(entry.pid)
              end
            end
          end
        end
      end
    end
  end
end
