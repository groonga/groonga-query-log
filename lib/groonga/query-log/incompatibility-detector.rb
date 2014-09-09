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

require "groonga/query-log/parser"

module Groonga
  module QueryLog
    class IncompatibilityDetector
      attr_reader :version
      def initialize(version)
        @version = version
      end

      private
      def build_message(command, parameter, description, value)
        components = [
          command,
          parameter,
          description,
          "<#{value}>",
        ]
        components.join(": ")
      end

      class Version1 < self
        def initialize
          super(1)
        end

        def detect(statistic)
          []
        end
      end

      class Version2 < self
        def initialize
          super(2)
        end

        def detect(statistic)
          case statistic.command.name
          when "select"
            detect_select(statistic)
          else
            []
          end
        end

        private
        def detect_select(statistic)
          command = statistic.command
          incompatibles = []
          space_delimiter_unacceptable_parameters = ["output_columns"]
          space_delimiter_unacceptable_parameters.each do |parameter|
            value = command[parameter]
            if space_delimiter?(value)
              description = "space is used as delimiter"
              message = build_message("select", parameter, description, value)
              incompatibles << message
            end
          end
          incompatibles
        end

        def space_delimiter?(string)
          return false if string.nil?
          return false if have_function_call?(string)
          string.split(/\s+/) != string.split(/\s*,\s*/)
        end

        def have_function_call?(string)
          string.include?("(")
        end
      end
    end
  end
end
