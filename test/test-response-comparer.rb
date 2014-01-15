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

class ResponseComparerTest < Test::Unit::TestCase
  private
  def comparer(response1, response2)
    Groonga::QueryLog::ResponseComparer.new(@command, response1, response2)
  end

  def same?(response1, response2)
    comparer(response1, response2).same?
  end

  class SelectTest < self
    def setup
      @command = Groonga::Command::Select.new("select", {})
    end

    class ScorerTest < self
      class RandTest < self
        def setup
          super
          @command["scorer"] = "_score=rand()"
          @command["sortby"] = "_score"
        end

        def test_different_order
          assert_true(same?([[[3], [["_id", "UInt32"]], [1], [2], [3]]],
                            [[[3], [["_id", "UInt32"]], [3], [2], [1]]]))
        end

        def test_different_attributes
          assert_false(same?([[[3], [["_id", "UInt32"]], [1], [2], [3]]],
                             [[[3], [["age", "UInt32"]], [1], [2], [3]]]))
        end

        def test_different_n_records
          assert_false(same?([[[3], [["_id", "UInt32"]], [1], [2]]],
                             [[[3], [["_id", "UInt32"]], [1], [2], [3]]]))
        end
      end

      class DetectRandTest < self
        def test_rand_only
          assert_true(random_score?("_score=rand()"))
        end

        private
        def random_score?(scorer)
          @command["scorer"] = scorer
          comparer([], []).send(:random_score?)
        end
      end
    end
  end
end
