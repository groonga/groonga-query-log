# -*- coding: utf-8 -*-
#
# Copyright (C) 2013  Kouhei Sutou <kou@clear-code.com>
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

class ReplayerTest < Test::Unit::TestCase
  class OptionTest < self
    def setup
      @options = Groonga::QueryLog::Replayer::Options.new
      @options.n_clients = 1
    end

    def test_host
      host = "example.com"
      @options.host = host
      mock_client_open(:host => host)
      replay
    end

    def test_port
      port = 2929
      @options.port = 2929
      mock_client_open(:port => 2929)
      replay
    end

    private
    def replay
      replayer = Groonga::QueryLog::Replayer.new(@options)
      replayer.replay(StringIO.new(""))
    end

    def mock_client_open(expected_options)
      client = Object.new
      default_options = {
        :host     => "127.0.0.1",
        :port     => 10041,
        :protocol => :gqtp,
      }
      expected_open_options = default_options.merge(expected_options)
      mock(Groonga::Client).open(expected_open_options).yields(client) do
        client
      end
    end
  end
end
