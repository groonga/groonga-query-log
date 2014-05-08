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
    response1 = normalize_response(response1)
    response2 = normalize_response(response2)
    Groonga::QueryLog::ResponseComparer.new(@command, response1, response2)
  end

  def same?(response1, response2)
    comparer(response1, response2).same?
  end

  def response(body)
    header = [0, 0.0, 0.0]
    response_class = Groonga::Client::Response.find(@command.name)
    response_class.new(@command, header, body)
  end

  def error_response(header)
    Groonga::Client::Response::Error.new(@command, header, [])
  end

  def normalize_response(response_or_body)
    if response_or_body.is_a?(Groonga::Client::Response::Base)
      response_or_body
    else
      response(response_or_body)
    end
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
          comparer([[[0]]], [[[0]]]).send(:random_score?)
        end
      end
    end

    class SortbyTest < self
      class DetectScoreSortTest < self
        private
        def score_sort?(sortby)
          @command["sortby"] = sortby
          comparer([[[0]]], [[[0]]]).send(:score_sort?)
        end

        class NoScoreTest < self
          def test_nil
            assert_false(score_sort?(nil))
          end

          def test_empty
            assert_false(score_sort?(""))
          end
        end

        class ScoreOnly < self
          def test_no_sign
            assert_true(score_sort?("_score"))
          end

          def test_plus
            assert_true(score_sort?("+_score"))
          end

          def test_minus
            assert_true(score_sort?("-_score"))
          end
        end

        class MultipleItemsTest < self
          def test_no_space
            assert_true(score_sort?("_id,_score,_key"))
          end

          def test_have_space
            assert_true(score_sort?("_id, _score, _key"))
          end

          def test_plus
            assert_true(score_sort?("_id,+_score,_key"))
          end

          def test_minus
            assert_true(score_sort?("_id,-_score,_key"))
          end
        end
      end
    end

    class ErrorTest < self
      def test_with_location
        response1_header = [
          -63,
          1.0,
          0.1,
          "Syntax error! ()",
          [
            ["yy_syntax_error", "ecmascript.lemon", 24],
          ],
        ]
        response2_header = JSON.parse(response1_header.to_json)
        response2_header[4][0][2] += 1
        assert_not_equal(response1_header, response2_header)

        response1 = error_response(response1_header)
        response2 = error_response(response2_header)
        assert_true(same?(response1, response2))
      end
    end
  end
end
