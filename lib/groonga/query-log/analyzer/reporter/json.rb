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

require "groonga/query-log/analyzer/reporter"

module Groonga
  module QueryLog
    class Analyzer
      class JSONReporter < Reporter
        def report_statistic(statistic)
          write(",") if @index > 0
          write("\n")
          write(format_statistic(statistic))
          @index += 1
        end

        def start
          @index = 0
          write("[")
        end

        def finish
          write("\n")
          write("]\n")
        end

        def report_summary
          # TODO
        end

        private
        def format_statistic(statistic)
          data = {
            "start_time" => statistic.start_time.to_i,
            "last_time" => statistic.last_time.to_i,
            "elapsed" => statistic.elapsed_in_seconds,
            "return_code" => statistic.return_code,
            "slow" => statistic.slow?,
          }
          command = statistic.command
          arguments = command.arguments.collect do |key, value|
            {"key" => key, "value" => value}
          end
          data["command"] = {
            "raw" => statistic.raw_command,
            "name" => command.name,
            "parameters" => arguments,
          }
          operations = []
          statistic.each_operation do |operation|
            operation_data = {}
            operation_data["name"] = operation[:name]
            operation_data["relative_elapsed"] = operation[:relative_elapsed_in_seconds]
            operation_data["context"] = operation[:context]
            operation_data["slow"] = operation[:slow?]
            operations << operation_data
          end
          data["operations"] = operations
          JSON.generate(data)
        end
      end
    end
  end
end
