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

module Groonga
  module QueryLog
    class Analyzer
      class SizedGroupedOperations < Array
        def initialize
          @max_size = 10
          @sorter = create_sorter
        end

        def apply_options(options)
          @max_size = options[:n_entries]
        end

        def each
          i = 0
          super do |grouped_operation|
            break if i >= @max_size
            i += 1
            yield(grouped_operation)
          end
        end

        def <<(operation)
          each do |grouped_operation|
            if grouped_operation[:name] == operation[:name] and
                grouped_operation[:context] == operation[:context]
              elapsed = operation[:relative_elapsed_in_seconds]
              grouped_operation[:total_elapsed] += elapsed
              grouped_operation[:n_operations] += 1
              replace(sort_by(&@sorter))
              return self
            end
          end

          grouped_operation = {
            :name => operation[:name],
            :context => operation[:context],
            :n_operations => 1,
            :total_elapsed => operation[:relative_elapsed_in_seconds],
          }
          buffer_size = @max_size * 100
          if size < buffer_size
            super(grouped_operation)
            replace(sort_by(&@sorter))
          else
            if @sorter.call(grouped_operation) < @sorter.call(last)
              super(grouped_operation)
              sorted_operations = sort_by(&@sorter)
              sorted_operations.pop
              replace(sorted_operations)
            end
          end
          self
        end

        private
        def create_sorter
          lambda do |grouped_operation|
            -grouped_operation[:total_elapsed]
          end
        end
      end
    end
  end
end
