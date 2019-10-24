# Copyright (C) 2019  Kentaro Hayashi <hayashi@clear-code.com>
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

class PerformanceVerifierTest < Test::Unit::TestCase
  def setup
    @old_responses = build_responses([0.3, 0.2, 0.1])
    @new_responses = build_responses([0.9, 0.5, 0.7])
  end

  def build_responses(elapsed_times)
    elapsed_times.collect do |elapsed_time|
      header = [0, 0, elapsed_time]
      Groonga::Client::Response::Base.new(nil, header, nil)
    end
  end

  def test_old_elapsed_time
    verifier = GroongaQueryLog::PerformanceVerifier.new(nil, @old_responses, @new_responses)
    assert_equal(0.1, verifier.old_elapsed_time)
  end

  def test_new_elapsed_time
    verifier = GroongaQueryLog::PerformanceVerifier.new(nil, @old_responses, @new_responses)
    assert_equal(0.5, verifier.new_elapsed_time)
  end
end
