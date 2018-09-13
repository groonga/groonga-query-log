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

class FilterRewriterTest < Test::Unit::TestCase
  private
  def rewrite(filter, options)
    rewriter = GroongaQueryLog::FilterRewriter.new(filter, options)
    rewriter.rewrite
  end

  class VectorEqualTest < self
    def rewrite_vector_equal(filter, vector_accessors)
      rewrite(filter,
              :rewrite_vector_equal => true,
              :vector_accessors => vector_accessors)
    end

    def test_not_target_accessor
      assert_equal("vector == \"value\"",
                   rewrite_vector_equal("vector == \"value\"",
                                        ["nonexistent"]))
    end

    def test_parenthesis
      assert_equal("((vector @ \"value\"))",
                   rewrite_vector_equal("((vector == \"value\"))",
                                        ["vector"]))
    end

    def test_under_score
      assert_equal("vector_column @ \"value\"",
                   rewrite_vector_equal("vector_column == \"value\"",
                                        ["vector_column"]))
    end
  end
end
