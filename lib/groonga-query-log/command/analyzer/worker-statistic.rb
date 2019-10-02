# Copyright (C) 2019  Sutou Kouhei <kou@clear-code.com>
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

module GroongaQueryLog
  module Command
    class Analyzer
      class WorkerStatistic
        attr_reader :id
        attr_reader :idle_time_total
        attr_reader :idle_time_mean
        attr_reader :idle_time_min
        attr_reader :idle_time_max
        def initialize(id)
          @id = id
          @idle_time_total = 0.0
          @idle_time_mean = 0.0
          @idle_time_min = 0.0
          @idle_time_max = 0.0
          @n_statistics = 0
          @previous_statistic = nil
        end

        def <<(statistic)
          @n_statistics += 1
          if @previous_statistic
            idle_time = statistic.start_time - @previous_statistic.end_time
            @idle_time_total += idle_time
            @idle_time_mean += ((idle_time - @idle_time_mean) / @n_statistics)
            if @idle_time_min.zero?
              @idle_time_min = idle_time
            else
              @idle_time_min = [@idle_time_min, idle_time].min
            end
            @idle_time_max = [@idle_time_max, idle_time].max
          end
          @previous_statistic = statistic
        end
      end
    end
  end
end
