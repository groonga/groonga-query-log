# Copyright (C) 2014  Kouhei Sutou <kou@clear-code.com>
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

require "groonga/query-log/incompatibility-detector"

module Groonga
  module QueryLog
    class CommandVersionCompatibilityChecker
      def initialize(options)
        @options = options
        @incompatibility_detector = @options.create_incompatibility_detector
        @output = $stdout
        @nth_item = 1
      end

      def start
        original_output = @output
        result = nil
        @options.create_output do |output|
          @output = output
          result = yield
        end
        result
      ensure
        @output = original_output
      end

      def check(input)
        compatible = true
        parser = Parser.new
        parser.parse(input) do |statistic|
          incompatibles = @incompatibility_detector.detect(statistic)
          next if incompatibles.empty?
          compatible = false
          incompatibles.each do |incompatible|
            report_incompatible(statistic, incompatible)
          end
        end
        compatible
      end

      private
      def report_incompatible(statistic, incompatible)
        nth_item = @nth_item
        @nth_item += 1
        version = @incompatibility_detector.version
        start_time = statistic.start_time.strftime("%Y-%m-%d %H:%M:%S.%6N")
        @output.puts("#{nth_item}: version#{version}: #{incompatible}")
        @output.puts("  %s" % start_time)
        @output.puts("  #{statistic.raw_command}")
        @output.puts("  Parameters:")
        statistic.command.arguments.each do |key, value|
          @output.puts("    <#{key}>: <#{value}>")
        end
      end

      class Options
        attr_accessor :target_version
        attr_accessor :output_path
        def initialize
          @target_version = 2
          @output_path = nil
        end

        def create_incompatibility_detector
          case @target_version
          when 1
            IncompatibilityDetector::Version1.new
          when 2
            IncompatibilityDetector::Version2.new
          else
            raise ArgumentError, "Unsupported version: #{@target_version}"
          end
        end

        def create_output(&block)
          if @output_path
            FileUtils.mkdir_p(File.dirname(@output_path))
            File.open(@output_path, "w", &block)
          else
            yield($stdout)
          end
        end
      end
    end
  end
end
