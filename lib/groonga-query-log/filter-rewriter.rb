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

module GroongaQueryLog
  class FilterRewriter
    def initialize(filter, options={})
      @filter = filter
      @options = options
      @vector_accessors = @options[:vector_accessors] || []
    end

    def rewrite
      rewritten = @filter
      if @options[:rewrite_vector_equal]
        rewritten = rewrite_vector_equal(rewritten)
      end
      if @options[:rewrite_vector_not_equal_empty_string]
        rewritten = rewrite_vector_not_equal_empty_string(rewritten)
      end
      rewritten
    end

    private
    def rewrite_vector_equal(filter)
      filter.gsub(/([a-zA-Z0-9_.]+) *==/) do |matched|
        variable = $1
        if @vector_accessors.include?(variable)
          "#{variable} @"
        else
          matched
        end
      end
    end

    def rewrite_vector_not_equal_empty_string(filter)
      filter.gsub(/([a-zA-Z0-9_.]+) *!= *(?:''|"")/) do |matched|
        variable = $1
        if @vector_accessors.include?(variable)
          "false"
        else
          matched
        end
      end
    end
  end
end
