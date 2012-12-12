# -*- coding: utf-8 -*-
#
# Copyright (C) 2011-2012  Kouhei Sutou <kou@clear-code.com>
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

require "English"

require "groonga/query-log/analyzer/statistics"

module Groonga
  module QueryLog
    class Parser
      def initialize
      end

      def parse(input, &block)
        current_statistics = {}
        input.each_line do |line|
          case line
          when /\A(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)\.(\d+)\|(.+?)\|([>:<])/
            year, month, day, hour, minutes, seconds, micro_seconds =
              $1, $2, $3, $4, $5, $6, $7
            context_id = $8
            type = $9
            rest = $POSTMATCH.strip
            time_stamp = Time.local(year, month, day, hour, minutes, seconds,
                                    micro_seconds)
            parse_line(current_statistics,
                       time_stamp, context_id, type, rest, &block)
          end
        end
      end

      private
      def parse_line(current_statistics,
                     time_stamp, context_id, type, rest, &block)
        case type
        when ">"
          statistic = Statistic.new(context_id)
          statistic.start(time_stamp, rest)
          current_statistics[context_id] = statistic
        when ":"
          return unless /\A(\d+) (.+)\((\d+)\)/ =~ rest
          elapsed = $1
          name = $2
          n_records = $3.to_i
          statistic = current_statistics[context_id]
          return if statistic.nil?
          statistic.add_operation(:name => name,
                                  :elapsed => elapsed.to_i,
                                  :n_records => n_records)
        when "<"
          return unless /\A(\d+) rc=(\d+)/ =~ rest
          elapsed = $1
          return_code = $2
          statistic = current_statistics.delete(context_id)
          return if statistic.nil?
          statistic.finish(elapsed.to_i, return_code.to_i)
          block.call(statistic)
        end
      end
    end
  end
end
