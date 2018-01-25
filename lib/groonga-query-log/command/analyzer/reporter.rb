# Copyright (C) 2011-2018  Kouhei Sutou <kou@clear-code.com>
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

require "time"

module GroongaQueryLog
  module Command
    class Analyzer
      class Reporter
        include Enumerable

        attr_reader :output
        attr_accessor :slow_operation_threshold, :slow_response_threshold
        def initialize(statistics, options={})
          @statistics = statistics
          @options = options
          self.output = @options[:output] || $stdout
          @report_summary = @options[:report_summary]
          @report_summary = true if @report_summary.nil?
          @report_command_line = @options[:report_command_line]
          @report_command_line = true if @report_command_line.nil?
          @slow_operation_threshold =
            @options[:slow_operation_threshold] ||
            Statistic::DEFAULT_SLOW_OPERATION_THRESHOLD
          @slow_response_threshold =
            @options[:slow_response_threshold] ||
            Statistic::DEFAULT_SLOW_RESPONSE_THRESHOLD
        end

        def output=(output)
          @output = output
          @output = $stdout if @output == "-"
        end

        def each
          @statistics.each do |statistic|
            yield statistic
          end
        end

        def report
          setup do
            report_summary if @report_summary
            report_statistics
          end
        end

        def report_statistics
          each do |statistic|
            report_statistic(statistic)
          end
        end

        private
        def setup
          setup_output do
            start
            yield
            finish
          end
        end

        def setup_output
          original_output = @output
          if @output.is_a?(String)
            File.open(@output, "w") do |output|
              @output = output
              yield(@output)
            end
          else
            yield(@output)
          end
        ensure
          @output = original_output
        end

        def write(*args)
          @output.write(*args)
        end

        def format_time(time)
          if time.nil?
            "NaN"
          else
            time.iso8601(6)
          end
        end
      end
    end
  end
end
