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
  module Formattable
    private
    def format_elapsed_time(elapsed_time)
      if elapsed_time < (1 / 1000.0 / 1000.0)
        "%.1fnsec" % (elapsed_time * 1000 * 1000)
      elsif elapsed_time < (1 / 1000.0)
        "%.1fusec" % (elapsed_time * 1000 * 1000)
      elsif elapsed_time < 1
        "%.1fmsec" % (elapsed_time * 1000)
      elsif elapsed_time < 60
        "%.1fsec" % elapsed_time
      else
        "%.1fmin" % (elapsed_time / 60)
      end
    end

    def format_elapsed_times(elapsed_times)
      formatted_epalsed_times = elapsed_times.collect do |elapsed_time|
        format_elapsed_time(elapsed_time)
      end
      formatted_epalsed_times.join(" ")
    end
  end
end
