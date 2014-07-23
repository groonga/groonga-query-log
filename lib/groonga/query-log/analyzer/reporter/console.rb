# -*- coding: utf-8 -*-
#
# Copyright (C) 2011-2014  Kouhei Sutou <kou@clear-code.com>
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

require "groonga/query-log/analyzer/reporter"

module Groonga
  module QueryLog
    class Analyzer
      class ConsoleReporter < Reporter
        class Color
          NAMES = [
            "black",
            "red",
            "green",
            "yellow",
            "blue",
            "magenta",
            "cyan",
            "white",
          ]

          attr_reader :name
          def initialize(name, options={})
            @name = name
            @foreground = options[:foreground]
            @foreground = true if @foreground.nil?
            @intensity = options[:intensity]
            @bold = options[:bold]
            @italic = options[:italic]
            @underline = options[:underline]
          end

          def foreground?
            @foreground
          end

          def intensity?
            @intensity
          end

          def bold?
            @bold
          end

          def italic?
            @italic
          end

          def underline?
            @underline
          end

          def ==(other)
            self.class === other and
              [name, foreground?, intensity?,
               bold?, italic?, underline?] ==
              [other.name, other.foreground?, other.intensity?,
               other.bold?, other.italic?, other.underline?]
          end

          def sequence
            sequence = []
            if @name == "none"
            elsif @name == "reset"
              sequence << "0"
            else
              foreground_parameter = foreground? ? 3 : 4
              foreground_parameter += 6 if intensity?
              sequence << "#{foreground_parameter}#{NAMES.index(@name)}"
            end
            sequence << "1" if bold?
            sequence << "3" if italic?
            sequence << "4" if underline?
            sequence
          end

          def escape_sequence
            "\e[#{sequence.join(';')}m"
          end

          def +(other)
            MixColor.new([self, other])
          end
        end

        class MixColor
          attr_reader :colors
          def initialize(colors)
            @colors = colors
          end

          def sequence
            @colors.inject([]) do |result, color|
              result + color.sequence
            end
          end

          def escape_sequence
            "\e[#{sequence.join(';')}m"
          end

          def +(other)
            self.class.new([self, other])
          end

          def ==(other)
            self.class === other and colors == other.colors
          end
        end

        def initialize(statistics)
          super
          @color = :auto
          @reset_color = Color.new("reset")
          @color_schema = {
            :elapsed => {:foreground => :white, :background => :green},
            :time => {:foreground => :white, :background => :cyan},
            :slow => {:foreground => :white, :background => :red},
          }
        end

        def apply_options(options)
          super
          @color = options[:color] || @color
        end

        def report_statistics
          write("\n")
          write("Slow Queries:\n")
          super
        end

        def report_statistic(statistic)
          @index += 1
          write("%*d) %s" % [@digit, @index, format_heading(statistic)])
          report_parameters(statistic)
          report_operations(statistic)
        end

        def start
          @index = 0
          if @statistics.size.zero?
            @digit = 1
          else
            @digit = Math.log10(@statistics.size).truncate + 1
          end
        end

        def finish
        end

        private
        def setup
          super do
            setup_color do
              yield
            end
          end
        end

        def report_summary
          write("Summary:\n")
          write("  Threshold:\n")
          write("    slow response     : #{@slow_response_threshold}\n")
          write("    slow operation    : #{@slow_operation_threshold}\n")
          write("  # of responses      : #{@statistics.n_responses}\n")
          write("  # of slow responses : #{@statistics.n_slow_responses}\n")
          write("  responses/sec       : #{@statistics.responses_per_second}\n")
          write("  start time          : #{format_time(@statistics.start_time)}\n")
          write("  last time           : #{format_time(@statistics.last_time)}\n")
          write("  period(sec)         : #{@statistics.period}\n")
          slow_response_ratio = @statistics.slow_response_ratio
          write("  slow response ratio : %5.3f%%\n" % slow_response_ratio)
          write("  total response time : #{@statistics.total_elapsed}\n")
          report_slow_operations
        end

        def report_slow_operations
          write("  Slow Operations:\n")
          total_elapsed_digit = nil
          total_elapsed_decimal_digit = 6
          n_operations_digit = nil
          @statistics.each_slow_operation do |grouped_operation|
            total_elapsed = grouped_operation[:total_elapsed]
            total_elapsed_digit ||= Math.log10(total_elapsed).truncate + 1
            n_operations = grouped_operation[:n_operations]
            n_operations_digit ||= Math.log10(n_operations).truncate + 1
            parameters = [total_elapsed_digit + 1 + total_elapsed_decimal_digit,
                          total_elapsed_decimal_digit,
                          total_elapsed,
                          grouped_operation[:total_elapsed_ratio],
                          n_operations_digit,
                          n_operations,
                          grouped_operation[:n_operations_ratio],
                          grouped_operation[:name],
                          grouped_operation[:context]]
            write("    [%*.*f](%5.2f%%) [%*d](%5.2f%%) %9s: %s\n" % parameters)
          end
        end

        def report_parameters(statistic)
          command = statistic.command
          write("  name: <#{command.name}>\n")
          write("  parameters:\n")
          command.arguments.each do |key, value|
            write("    <#{key}>: <#{value}>\n")
          end
        end

        def report_operations(statistic)
          statistic.each_operation do |operation|
            relative_elapsed_in_seconds = operation[:relative_elapsed_in_seconds]
            formatted_elapsed = "%8.8f" % relative_elapsed_in_seconds
            if operation[:slow?]
              formatted_elapsed = colorize(formatted_elapsed, :slow)
            end
            operation_report = " %2d) %s: %10s" % [operation[:i] + 1,
                                                   formatted_elapsed,
                                                   operation[:name]]
            if operation[:n_records]
              operation_report << "(%6d)" % operation[:n_records]
            else
              operation_report << "(%6s)" % ""
            end
            context = operation[:context]
            if context
              context = colorize(context, :slow) if operation[:slow?]
              operation_report << " " << context
            end
            write("#{operation_report}\n")
          end
          write("\n")
        end

        def guess_color_availability(output)
          return false unless output.tty?
          case ENV["TERM"]
          when /term(?:-color)?\z/, "screen"
            true
          else
            return true if ENV["EMACS"] == "t"
            false
          end
        end

        def setup_color
          color = @color
          @color = guess_color_availability(@output) if @color == :auto
          yield
        ensure
          @color = color
        end

        def format_heading(statistic)
          formatted_elapsed = colorize("%8.8f" % statistic.elapsed_in_seconds,
                                       :elapsed)
          "[%s-%s (%s)](%d): %s" % [format_time(statistic.start_time),
                                    format_time(statistic.last_time),
                                    formatted_elapsed,
                                    statistic.return_code,
                                    statistic.raw_command]
        end

        def format_time(time)
          colorize(super, :time)
        end

        def colorize(text, schema_name)
          return text unless @color
          options = @color_schema[schema_name]
          color = Color.new("none")
          if options[:foreground]
            color += Color.new(options[:foreground].to_s, :bold => true)
          end
          if options[:background]
            color += Color.new(options[:background].to_s, :foreground => false)
          end
          "%s%s%s" % [color.escape_sequence, text, @reset_color.escape_sequence]
        end
      end
    end
  end
end
