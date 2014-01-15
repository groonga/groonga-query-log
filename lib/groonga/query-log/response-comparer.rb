# -*- coding: utf-8 -*-
#
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

module Groonga
  module QueryLog
    class ResponseComparer
      def initialize(command, response1, response2)
        @command = command
        @response1 = response1
        @response2 = response2
      end

      def same?
        case @command.name
        when "select"
          same_select_response?
        else
          same_response?
        end
      end

      private
      def same_response?
        @response1 == @response2
      end

      def same_select_response?
        if random_sort?
          records_result1 = @response1[0] || []
          records_result2 = @response2[0] || []
          records_result1.size == records_result2.size and
            records_result1[0..1] == records_result2[0..1]
        else
          same_response?
        end
      end

      def random_score?
        @command.scorer == "_score=rand()"
      end

      def random_sort?
        random_score? and
          (@command.sortby || "").split(/\s*,\s*/).include?("_score")
      end
    end
  end
end
