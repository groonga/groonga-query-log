# Copyright (C) 2014-2018  Kouhei Sutou <kou@clear-code.com>
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
  def comparer(response1, response2, options={})
    response1 = normalize_response(response1)
    response2 = normalize_response(response2)
    GroongaQueryLog::ResponseComparer.new(@command, response1, response2,
                                          options)
  end

  def same?(response1, response2, options={})
    comparer(response1, response2, options).same?
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
          @command["output_columns"] = "_id"
          assert_true(same?([[[3], [["_id", "UInt32"]], [1], [2], [3]]],
                            [[[3], [["_id", "UInt32"]], [3], [2], [1]]]))
        end

        def test_different_attributes
          @command["output_columns"] = "_id, age"
          assert_false(same?([[[3], [["_id", "UInt32"]], [1], [2], [3]]],
                             [[[3], [["age", "UInt32"]], [1], [2], [3]]]))
        end

        def test_different_n_records
          @command["output_columns"] = "_id"
          assert_false(same?([[[3], [["_id", "UInt32"]], [1], [2]]],
                             [[[3], [["_id", "UInt32"]], [1], [2], [3]]]))
        end

        def test_all_output_columns
          assert_true(same?([
                              [
                                [3],
                                [["_id", "UInt32"], ["_key", "ShortText"]],
                                [1, "1"],
                                [2, "2"],
                                [3, "3"],
                              ],
                            ],
                            [
                              [
                                [3],
                                [["_key", "ShortText"], ["_id", "UInt32"]],
                                ["3", 3],
                                ["2", 2],
                                ["1", 1],
                              ],
                            ]))
        end
      end

      class DetectRandTest < self
        def test_rand_only
          assert_true(random_score?("_score=rand()"))
        end

        def test_with_spaces
          assert_true(random_score?("_score = rand()"))
        end

        private
        def random_score?(scorer)
          @command["scorer"] = scorer
          comparer([[[0], []]], [[[0], []]]).send(:random_score?)
        end
      end
    end

    class SortKeysTest < self
      class DetectScoreSortTest < self
        private
        def score_sort?(sort_keys)
          @command[:sort_keys] = sort_keys
          comparer([[[0], []]], [[[0], []]]).send(:score_sort?)
        end

        class ParameterNameTest < self
          def score_sort?(parameter_name)
            @command[parameter_name] = "_score"
            comparer([[[0], []]], [[[0], []]]).send(:score_sort?)
          end

          def test_sortby
            assert do
              score_sort?(:sortby)
            end
          end

          def test_sort_keys
            assert do
              score_sort?(:sort_keys)
            end
          end
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

    class OutputColumnsTest < self
      class AllTest < self
        def setup
          super
          @command["output_columns"] = "*"
        end

        def test_different_order
          assert_true(same?([
                              [
                                [3],
                                [["_id", "UInt32"], ["_key", "ShortText"]],
                                [1, "1"],
                                [2, "2"],
                                [3, "3"],
                              ],
                            ],
                            [
                              [
                                [3],
                                [["_key", "ShortText"], ["_id", "UInt32"]],
                                ["1", 1],
                                ["2", 2],
                                ["3", 3],
                              ],
                            ]))
        end

        def test_different_record
          assert_false(same?([
                               [
                                 [1],
                                 [["_id", "UInt32"], ["_key", "ShortText"]],
                                 [1, "1"],
                               ],
                             ],
                             [
                               [
                                 [1],
                                 [["_key", "ShortText"], ["_id", "UInt32"]],
                                 [2, "2"],
                               ],
                             ]))
        end
      end

      class DetectAllTest < self
        def test_star_only
          assert_true(all_output_columns?("*"))
        end

        def test_include_star
          assert_true(all_output_columns?("_key, _value, *"))
        end

        def test_default
          assert_true(all_output_columns?(nil))
        end

        private
        def all_output_columns?(output_columns)
          @command["output_columns"] = output_columns if output_columns
          comparer([[[0], []]], [[[0], []]]).send(:all_output_columns?)
        end
      end

      class UnaryMinusTest < self
        def setup
          super
          @command["output_columns"] = "_id, -value"
        end

        def test_ignore
          response1 = [
            [
              [3],
              [
                ["_id", "UInt32"],
              ],
              [1],
              [2],
              [3],
            ],
          ]
          response2 = [
            [
              [3],
              [
                ["_id", "UInt32"],
                ["value", nil],
              ],
              [1, -11],
              [2, -12],
              [3, -13],
            ],
          ]
          assert do
            same?(response1, response2)
          end
        end
      end

      class DetectUnaryMinusTest < self
        def test_unary_minus_column_only
          assert do
            have_unary_minus_output_column?("-value")
          end
        end

        def test_include_unary_minus_column
          assert do
            have_unary_minus_output_column?("_id, -value")
          end
        end

        def test_nonexistent
          assert do
            not have_unary_minus_output_column?("_id, _key")
          end
        end

        private
        def have_unary_minus_output_column?(output_columns)
          @command["output_columns"] = output_columns if output_columns
          comparer([[[0], []]],
                   [[[0], []]]).send(:have_unary_minus_output_column?)
        end
      end
    end

    class ForceNoCareOrderTest < self
      def test_different_order
        @command["output_columns"] = "_id"
        assert_true(same?([[[3], [["_id", "UInt32"]], [1], [2], [3]]],
                          [[[3], [["_id", "UInt32"]], [3], [2], [1]]],
                          :care_order => false))
      end
    end

    class FloatAccurancy < self
      def create_response(latitude, longitude)
        [
          [
            [1],
            [["_id", "UInt32"], ["latitude", "Float"], ["longitude", "Float"]],
            [1, latitude, longitude],
          ]
        ]
      end

      def test_all_output_columns
        response1 = create_response(35.6562002690605,  139.763570507358)
        response2 = create_response(35.65620026906051, 139.7635705073576)
        assert do
          same?(response1, response2)
        end
      end

      def test_unary_minus_output_column
        @command["output_columns"] = "_id, -value, latitude, longitude"
        response1 = create_response(35.6562002690605,  139.763570507358)
        response2 = create_response(35.65620026906051, 139.7635705073576)
        assert do
          same?(response1, response2)
        end
      end

      def test_specific_output_columns
        @command["output_columns"] = "_id, latitude, longitude"
        response1 = create_response(35.6562002690605,  139.763570507358)
        response2 = create_response(35.65620026906051, 139.7635705073576)
        assert do
          same?(response1, response2)
        end
      end
    end

    class DrilldownTest < self
      def create_response(drilldown)
        [
          [
            [10],
            [["_id", "UInt32"]],
          ],
          [
            [drilldown.size * 2],
            [["_key", "ShortText"], ["_nsubrecs", "Int32"]],
            *drilldown,
          ]
        ]
      end

      def test_same
        response1 = create_response([["A", 10], ["B", 2]])
        response2 = create_response([["A", 10], ["B", 2]])
        assert do
          same?(response1, response2)
        end
      end

      def test_not_same
        response1 = create_response([["A", 11], ["B", 2]])
        response2 = create_response([["A", 10], ["B", 2]])
        assert do
          not same?(response1, response2)
        end
      end

      class IgnoreDrilldownKeysTest < self
        def create_response(drilldown1, drilldown2)
          [
            [
              [10],
              [["_id", "UInt32"]],
            ],
            [
              [drilldown1.size * 2],
              [["_key", "ShortText"], ["_nsubrecs", "Int32"]],
              *drilldown1,
            ],
            [
              [drilldown2.size * 2],
              [["_key", "ShortText"], ["_nsubrecs", "Int32"]],
              *drilldown2,
            ],
          ]
        end

        def test_same
          @command["drilldown"] = "column1, column2"
          response1 = create_response([["A", 10], ["B", 2]],
                                      [["a", 11], ["b", 10]])
          response2 = create_response([["A", 10], ["B", 2]],
                                      [["a", 99], ["b", 20]])
          assert do
            same?(response1, response2, ignored_drilldown_keys: ["column2"])
          end
        end

        def test_not_same
          @command["drilldown"] = "column1, column2"
          response1 = create_response([["A", 10], ["B", 2]],
                                      [["a", 11], ["b", 10]])
          response2 = create_response([["A", 10], ["B", 2]],
                                      [["a", 99], ["b", 20]])
          assert do
            not same?(response1, response2)
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
