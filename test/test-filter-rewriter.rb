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
    def rewrite(filter, vector_accessors)
      super(filter,
            :rewrite_vector_equal => true,
            :vector_accessors => vector_accessors)
    end

    def test_not_target_accessor
      assert_equal("vector == \"value\"",
                   rewrite("vector == \"value\"",
                           ["nonexistent"]))
    end

    def test_parenthesis
      assert_equal("((vector @ \"value\"))",
                   rewrite("((vector == \"value\"))",
                           ["vector"]))
    end

    def test_under_score
      assert_equal("vector_column @ \"value\"",
                   rewrite("vector_column == \"value\"",
                           ["vector_column"]))
    end
  end

  class VectorNotEqualEmptyStringTest < self
    def rewrite(filter, vector_accessors)
      super(filter,
            :rewrite_vector_not_equal_empty_string => true,
            :vector_accessors => vector_accessors)
    end

    def test_not_target_accessor
      assert_equal("vector != \"\"",
                   rewrite("vector != \"\"",
                           ["nonexistent"]))
    end

    def test_parenthesis
      assert_equal("((vector_size(vector) > 0))",
                   rewrite("((vector != \"\"))",
                           ["vector"]))
    end

    def test_under_score
      assert_equal("vector_size(vector_column) > 0",
                   rewrite("vector_column != \"\"",
                           ["vector_column"]))
    end

    def test_vector_sub_path
      assert_equal("vector_size(vector) > 0",
                    rewrite("vector.column != \"\"",
                            ["vector"]))
    end

    def test_reference_vector
      assert_equal("vector_size(reference.vector) > 0",
                    rewrite("reference.vector != \"\"",
                            ["reference.vector"]))
    end
  end

  class NullableReferenceNumberTest < self
    def rewrite(filter, accessors)
      super(filter,
            :rewrite_nullable_reference_number => true,
            :nullable_reference_number_accessors => accessors)
    end

    def test_not_target_accessor
      assert_equal("reference.number < 1000",
                   rewrite("reference.number < 1000",
                           ["nonexistent"]))
    end

    def test_parenthesis
      assert_equal("(((reference._key == null ? 0 : reference.number)) < 1000)",
                   rewrite("((reference.number) < 1000)",
                           ["reference.number"]))
    end

    def test_under_score
      assert_equal("(ref_column._key == null ? 0 : ref_column.number) < 1000",
                   rewrite("ref_column.number < 1000",
                           ["ref_column.number"]))
    end
  end

  class RegularExpressionTest < self
    def rewrite(filter, enabled = true)
      super(filter,
            :rewrite_not_or_regular_expression => enabled)
    end

    def test_rewrite_one
      assert_equal("column1 @ \"value1\" &! column2 @ \"value2\"",
                   rewrite("column1 @ \"value1\" && column2 @~ \"^(?!.*value2).+$\""))
    end

    def test_reference
      assert_equal("column1 @ \"value1\" &! reference.column2 @ \"value2\"",
                   rewrite("column1 @ \"value1\" && reference.column2 @~ \"^(?!.*value2).+$\""))
    end

    def test_under_score
      assert_equal("column1 @ \"value1\" &! column_2 @ \"value_2\"",
                   rewrite("column1 @ \"value1\" && column_2 @~ \"^(?!.*value_2).+$\""))
    end

    def test_rewrite_multiple
      assert_equal("column1 @ \"value1\" &! column2 @ \"value2\" &! column2 @ \"value3\" &! column2 @ \"value4\"",
                   rewrite("column1 @ \"value1\" && column2 @~ \"^(?!.*value2 | value3 | value4).+$\""))
    end
  end

  class AndNotOperatorTest < self
    def rewrite(filter, enabled = true)
      super(filter,
            :rewrite_and_not_operator => enabled)
    end

    def test_rewrite_one
      assert_equal("(column1 @ \"value1\") &! (column2 @ \"value2\")",
                   rewrite("(column1 @ \"value1\") && ! (column2 @ \"value2\")"))
    end

    def test_reference
      assert_equal("(column1 @ \"value1\") &! (reference.column2 @ \"value2\")",
                   rewrite("(column1 @ \"value1\") && ! (reference.column2 @ \"value2\")"))
    end

    def test_under_score
      assert_equal("(column1 @ \"value1\") &! (column_2 @ \"value2\")",
                   rewrite("(column1 @ \"value1\") && ! (column_2 @ \"value2\")"))
    end

    def test_rewrite_multiple
      assert_equal("(column1 @ \"value1\") &! (column2 @ \"value2\") &! (column2 @ \"value3\")",
                   rewrite("(column1 @ \"value1\") && ! (column2 @ \"value2\") && ! (column2 @ \"value3\")"))
    end
  end
end
