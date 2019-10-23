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
  class PerformanceVerifier
    def initialize(command, old_responses, new_responses)
      @command = command
      @old_responses = old_responses
      @new_responses = new_responses
      @threshold_diff = 0.1
      @threshold_ratio = 1.1
    end

    def slow?
      if error?(@old_responses) or error?(@new_responses)
        return false
      end

      if (old_elapsed_time - new_elapsed_time).abs < @threshold_diff
        return false
      end

      diff_ratio > @threshold_ratio
    end

    def old_elapsed_time
      decide_target_elapsed_time(@old_responses)
    end

    def new_elapsed_time
      decide_target_elapsed_time(@new_responses)
    end

    def diff_ratio
      compute_diff_ratio
    end

    private
    def error?(responses)
      responses.any? do |response|
        response.is_a?(Groonga::Client::Response::Error)
      end
    end

    def decide_target_elapsed_time(responses)
      elapsed_times = responses.collect do |response|
        response.elapsed_time
      end
      elapsed_times.sort.first
    end

    def compute_diff_ratio
      if old_elapsed_time.zero?
        1.0
      else
        new_elapsed_time / old_elapsed_time
      end
    end
  end
end
