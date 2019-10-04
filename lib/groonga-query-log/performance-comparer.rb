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
      diff_sec = compute_diff_sec(@response1, @response2)
      diff_ratio = comupte_diff_ratio(@response1, @response2)
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

    def compute_diff_sec(responses1, responses2)
      diffs = []
      responses1.each_with_index do |response1, response1_index|
        response2 = responses2[response1_index]
        diffs << (response1.header[2] - response2.header[2])
      end
      median = compute_median(diffs)
      diffs.sort[median]
    end

    def compute_diff_ratio(responses1, responses2)
      #todo
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
