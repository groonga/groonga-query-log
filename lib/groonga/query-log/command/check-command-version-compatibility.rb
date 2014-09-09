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

require "optparse"

require "groonga/query-log"

module Groonga
  module QueryLog
    module Command
      class CheckCommandVersionCompatibility
        def initialize
          @options = CommandVersionCompatibilityChecker::Options.new
        end

        def run(command_line)
          input_paths = create_parser.parse(command_line)
          checker = CommandVersionCompatibilityChecker.new(@options)
          checker.start do
            compatible = true
            if input_paths.empty?
              compatible = false unless checker.check($stdin)
            else
              input_paths.each do |input_path|
                File.open(input_path) do |input|
                  compatible = false unless checker.check(input)
                end
              end
            end
            compatible
          end
        end

        private
        def create_parser
          parser = OptionParser.new
          parser.version = VERSION
          parser.banner += " QUERY_LOG1 QUERY_LOG2 ..."

          parser.separator("")
          parser.separator("Options:")

          parser.on("--target-version=VERSION", Integer,
                    "Check incompatibility against command version VERSION",
                    "[#{@options.target_version}]") do |version|
            @options.target_version = version
          end

          parser.on("--output=PATH",
                    "Output results to PATH",
                    "[stdout]") do |path|
            @options.output_path = path
          end
        end
      end
    end
  end
end
