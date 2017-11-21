# Copyright (C) 2011-2017  Kouhei Sutou <kou@clear-code.com>
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

require "groonga-query-log/command/analyzer/reporter"

module GroongaQueryLog
  module Command
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
          JSON.generate(statistic.to_hash)
        end
      end
    end
  end
end
