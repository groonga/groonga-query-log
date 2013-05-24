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

require "thread"

require "groonga/client"

require "groonga/query-log/parser"

module Groonga
  module QueryLog
    class Replayer
      attr_accessor :host
      attr_accessor :port
      attr_accessor :protocol
      def initialize
        @host = "127.0.0.1"
        @port = 10041
        @protocol = :gqtp
        @n_clients = 8
        @queue = Queue.new
      end

      def replay(input)
        producer = run_producer(input)
        consumers = run_consumers
        producer.join
        consumers.each(&:join)
      end

      private
      def create_client(&block)
        Groonga::Client.open(:host     => @host,
                             :port     => @port,
                             :protocol => @protocol,
                             &block)
      end

      def run_producer(input)
        Thread.new do
          parser = Parser.new
          id = 0
          parser.parse(input) do |statistic|
            @queue.push([id, statistic])
            id += 1
          end
          @n_clients.times do
            @queie.push(nil)
          end
        end
      end

      def run_consumers
        @n_clients.times.collect do
          client = create_client
          Thread.new do
            loop do
              id, statistic = @queue.pop
              break if id.nil?
              replay_command(client, id, statistic.command)
            end
            client.shutdown
          end
        end
      end

      def replay_command(client, id, command)
        client.execute(command)
      end
    end
  end
end
