# Copyright (C) 2018-2025  Sutou Kouhei <kou@clear-code.com>
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

        if log_paths.empty?
          puts(@option_parser.help)
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
        available_command_format = [:command, :uri]
        available_output_levels = [:info, :debug]
        @options = {
          command_format: :command,
          output_level: :info,
          pretty_print: true
        }

        @option_parser = OptionParser.new do |parser|
          parser.version = VERSION
          parser.banner += " LOG1 ..."
          parser.on("--command-format=FORMAT",
                    available_command_format,
                    "Specify the output format of the Groonga command that had a problem. [#{@options[:command_format]}]",
                    "(#{available_command_format.join(", ")})") do |format|
            @options[:command_format] = format
          end
          parser.on("--[no-]pretty-print",
                    "Specify to make command output easier to read. [#{@options[:pretty_print]}]",
                    "Only available when `--command-format=command` is specified.") do |boolean|
            @options[:pretty_print] = boolean
          end
          parser.on("--output-level=LEVEL",
                    available_output_levels,
                    "Specify the output level. [#{@options[:output_level]}]",
                    "Specifying 'debug' displays detailed information.",
                    "(#{available_output_levels.join(", ")})") do |output_level|
            @options[:output_level] = output_level
          end
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
        checker = Checker.new(log_paths, @options)
        checker.check
      end

      class GroongaProcess
        attr_reader :version
        attr_reader :pid
        attr_reader :start_time
        attr_reader :start_log_path
        attr_accessor :end_time
        attr_accessor :end_log_path
        attr_accessor :n_leaks
        attr_writer :crashed
        attr_writer :finished
        attr_reader :important_entries
        def initialize(version, pid, start_time, start_log_path)
          @version = version
          @pid = pid
          @start_time = start_time
          @end_time = @start_time
          @start_log_path = start_log_path
          @end_log_path = @start_log_path
          @n_leaks = 0
          @crashed = false
          @finished = false
          @important_entries = []
        end

        def crashed?
          @crashed
        end

        def finished?
          @finished
        end

        def successfully_finished?
          return false if crashed?
          return false unless finished?

          true
        end
      end

      class Checker
        def initialize(log_paths, options)
          split_log_paths(log_paths)
          @options = options
        end

        def check
          summary = {
            crashed: false,
            unflushed: false,
            unfinished: false,
            leak: false,
          }
          processes = ProcessEnumerator.new(@general_log_paths)
          processes.each do |process|
            need_query_log_parsing = true
            if process.successfully_finished?
              need_query_log_parsing = false
              debug([:process,
                     :success,
                     process.version,
                     process.start_time.iso8601,
                     process.end_time.iso8601,
                     process.pid,
                     process.start_log_path,
                     process.end_log_path].inspect)
            elsif process.crashed?
              debug([:process,
                     :crashed,
                     process.version,
                     process.start_time.iso8601,
                     process.end_time.iso8601,
                     process.pid,
                     process.start_log_path,
                     process.end_log_path].inspect)
              summary[:crashed] = true
            else
              debug([:process,
                     :unfinished,
                     process.version,
                     process.start_time.iso8601,
                     process.pid,
                     process.start_log_path].inspect)
            end

            unless process.n_leaks.zero?
              debug([:leak,
                     process.version,
                     process.n_leaks,
                     process.end_time.iso8601,
                     process.pid,
                     process.end_log_path].inspect)
              summary[:leak] = true
            end

            unless process.important_entries.empty?
              output_important_entries_info(process.important_entries)
            end

            next unless need_query_log_parsing

            start_time = process.start_time
            end_time = process.end_time
            @flushed = true
            @unflushed_statistics = []
            query_log_parser = Parser.new
            query_log_parser.parse_paths(@query_log_paths) do |statistic|
              next if statistic.start_time < start_time
              break if statistic.start_time > end_time
              check_query_log_statistic(query_log_parser.current_path,
                                        statistic)
            end
            parsing_statistics = query_log_parser.parsing_statistics
            target_parsing_statistics = parsing_statistics.reject do |statistic|
              statistic.start_time < start_time
            end
            unless target_parsing_statistics.empty?
              summary[:unfinished] = true
              output_unfinished_info(target_parsing_statistics)
            end
            unless @unflushed_statistics.empty?
              summary[:unflushed] = true
              output_unflushed_info(start_time, end_time)
            end
          end
          info("",
               "Summary:",
               summary.map {|k, v| "#{k}:#{v ? "yes" : "no"}" }.join(", "))
          if summary.value?(true)
            info("NG: Please check the display and logs.")
          else
            info("OK: no problems.")
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

        def formated_command(command)
          if @options[:command_format] == :uri
            command.to_uri_format
          else
            (@options[:pretty_print] ? "\n" : "") +
              command.to_command_format(pretty_print: @options[:pretty_print])
          end
        end

        def check_query_log_statistic(path, statistic)
          command = statistic.command
          return if command.nil?

          case command.command_name
          when "load"
            @flushed = false
            @unflushed_statistics << statistic
          when "delete"
            @flushed = false
            @unflushed_statistics << statistic
          when "truncate"
            @flushed = false
            @unflushed_statistics << statistic
          when "io_flush"
            check_io_flush(command)
          when "database_unmap"
            @unflushed_statistics.reject! do |statistic|
              command.name == "load"
            end
          when "table_list", "column_list"
            # ignore
          when /\Atable_/
            @flushed = false
            @unflushed_statistics << statistic
          when /\Acolumn_/
            @flushed = false
            @unflushed_statistics << statistic
          when "plugin_register", "plugin_unregister"
            @flushed = false
            @unflushed_statistics << statistic
          end
        end

        def check_io_flush(io_flush)
          # TODO: Improve flushed target detection.
          if io_flush.target_name
            if io_flush.recursive?
              @unflushed_statistics.reject! do |statistic|
                case statistic.command.command_name
                when "load"
                  # TODO: Not enough
                  statistic.command.table == io_flush.target_name
                when "delete"
                  # TODO: Not enough
                  statistic.command.table == io_flush.target_name
                when "truncate"
                  # TODO: Not enough
                  statistic.command.target_name == io_flush.target_name
                else
                  false
                end
              end
            else
              @unflushed_statistics.reject! do |statistic|
                case statistic.command.command_name
                when /_create/
                  true # TODO: Need io_flush for database
                else
                  false
                end
              end
            end
          else
            if io_flush.recursive?
              @unflushed_statistics.clear
            else
              @unflushed_statistics.reject! do |statistic|
                case statistic.command.command_name
                when /_create\z/
                  true # TODO: Need io_flush for the target
                when /_remove\z/, /_rename\z/
                  true
                when "plugin_register", "plugin_unregister"
                  true
                else
                  false
                end
              end
            end
          end
          @flushed = @unflushed_statistics.empty?
        end

        def debug(*messages)
          return unless @options[:output_level] == :debug
          puts(*messages)
        end

        def info(*messages)
          puts(*messages)
        end

        def output_important_entries_info(entries)
          info("",
               "!!!",
               "!!! Important entries",
               "!!!",
               "It contained logs that require checking.",
               "If you need help, please feel free to contact the community: https://groonga.org/docs/community.html",
               "===")
          entries.each do |entry|
            info("#{entry.timestamp.iso8601}: " +
                 "#{entry.pid}: " +
                 "#{entry.thread_id}: " +
                 "#{entry.log_level}: " +
                 "#{entry.message}")
          end
          info("===")
        end

        def output_statistics_info(message, tag, statistics)
          info(message, "===")
          statistics.each do |statistic|
            info("[#{tag}] #{statistic.start_time.iso8601}: #{formated_command(statistic.command)}")
          end
          info("===")
        end

        def output_unfinished_info(statistics)
          message = <<-MESSAGE

!!!
!!! [unfinished] Recovery information
!!!
Unfinished commands were found due to abnormal termination or other issues.
It is safer to rebuild the target tables, columns, and indexes because the data may be corrupted.
          MESSAGE
          output_statistics_info(message, "unfinished", statistics)
        end

        def output_unflushed_info(start_time, end_time)
          message = <<-MESSAGE

!!!
!!! [unflushed] Recovery information
!!!
There may be commands that were not flushed between #{start_time.iso8601} and #{end_time.iso8601}.
These commands may not have been written to the database files, so please re-run them.
          MESSAGE
          output_statistics_info(message, "unflushed", @unflushed_statistics)
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
          when /\Agrn_init: <(.+?)>/, /\Amroonga (\d+\.\d+) started\.\z/
            version = $1
            process = @running_processes[entry.pid]
            if process
              process.finished = true
              process.crashed = true
              yield(process)
              @running_processes.delete(entry.pid)
            end
            process = GroongaProcess.new(version,
                                         entry.pid,
                                         entry.timestamp,
                                         path)
            @running_processes[entry.pid] = process
          when /\Agrn_fin \((\d+)\)\z/
            n_leaks = $1.to_i
            @running_processes[entry.pid] ||=
              GroongaProcess.new(nil, entry.pid, Time.at(0), path)
            process = @running_processes[entry.pid]
            process.n_leaks = n_leaks
            process.end_time = entry.timestamp
            process.end_log_path = path
            process.finished = true
            yield(process)
            @running_processes.delete(entry.pid)
          else
            @running_processes[entry.pid] ||=
              GroongaProcess.new(nil, entry.pid, Time.at(0), path)
            process = @running_processes[entry.pid]
            case entry.log_level
            when :notice
              case entry.message
              when /lock/
                process.important_entries << entry
              end
            when :emergency, :alert, :critical, :error
              process.important_entries << entry
            end
            process.end_time = entry.timestamp
            process.end_log_path = path
            case entry.message
            when "-- CRASHED!!! --"
              process.crashed = true
              process.finished = true
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
