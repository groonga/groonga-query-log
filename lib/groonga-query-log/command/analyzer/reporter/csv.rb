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

require "csv"
require "time"

require "groonga-query-log/command/analyzer/reporter"

module GroongaQueryLog
  module Command
    class Analyzer
      class CSVReporter < Reporter
        def initialize(statistics, options)
          super
          if @options[:report_command_line].nil?
            @report_command_line = false
          end
        end

        def start
          @csv = CSV.new(@output)
          header = [
            "start_time",
            "last_time",
            "elapsed",
            "return_code",
            "slow",
            "command_name",
          ]
          header << "command_line" if @report_command_line
          @csv << header
        end

        def report_statistic(statistic)
          record = [
            statistic.start_time.iso8601,
            statistic.last_time.iso8601,
            statistic.elapsed_in_seconds,
            statistic.return_code,
            statistic.slow?,
            statistic.command.name,
          ]
          record << statistic.raw_command if @report_command_line
          @csv << record
        end

        def finish
          @csv.close
        end

        def report_summary
        end
      end
    end
  end
end
