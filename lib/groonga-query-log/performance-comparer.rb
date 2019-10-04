# Copyright (C) 2019  Horimoto Yasuhiro <horimoto@clear-code.com>
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
  class PerformanceComparer
    def initialize(command, response1, response2)
      @command = command
      @response1 = response1
      @response2 = response2
      @threshold = Threshold.new
    end

    def slow?
      if error_response?(@response1) or error_response?(@response2)
        false
      end
      diff_sec = compute_diff_sec(new_elapsed_time(@response1),
                                  old_elapsed_time(@response2))
      diff_ratio = comupte_diff_ratio(new_elapsed_time(@response1),
                                      old_elapsed_time(@response2))
      @threshold.slow_query?(diff_sec, diff_ratio)
    end

    private
    def error_response?(responses)
      responses.each do |response|
        if response.is_a?(Groonga::Client::Response::Error)
          return true
        end
      end
      false
    end

    def compute_median(diffs)
      diffs.length % 2 == 0 ? diffs.length / 2 - 1 : diffs.length / 2
    end

    def new_elapsed_time(responses1)
      elapsed_times = []
      responses1.each do |response|
        elapsed_times << response.header[2]
      end
      median = compute_median(elapsed_times)
      elapsed_times.sort[median]
    end

    def old_elapsed_time(response2)
      elapsed_times = []
      responses1.each do |response|
        elapsed_times << response.header[2]
      end
      median = compute_median(elapsed_times)
      elapsed_times.sort[median]
    end

    def compute_diff_sec(new_elapsed_time, old_elapsed_time)
      new_elapsed_time - old_elapsed_time
    end

    def compute_diff_ratio(new_elapsed_time, new_elapsed_time)
      if new_elapsed_time.zero?
        if old_elapsed_times.zero?
          0.0
        end
        Float::INFINITY
      else
        new_elapsed_time / old_elapsed_time
      end
    end

    class Threshold
      attr_accessor:query_ratio
      attr_accessor:query_second
      def initialize
        @query_ratio = 0.1
        @query_second = 0.2
      end

      def slow_query?(diff_sec, diff_ratio)
        return false if diff_sec.zero?
        (diff_sec >= @query_second) and
          (diff_ratio >= @query_ratio)
      end
    end
  end
end
