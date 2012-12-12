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

module Groonga
  module QueryLog
    class Analyzer
    class Reporter
      include Enumerable

      attr_reader :output
      def initialize(statistics)
        @statistics = statistics
        @report_summary = true
        @output = $stdout
      end

      def apply_options(options)
        self.output = options[:output] || @output
        unless options[:report_summary].nil?
          @report_summary = options[:report_summary]
        end
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
          time.strftime("%Y-%m-%d %H:%M:%S.%u")
        end
      end
    end
    end
  end
end
