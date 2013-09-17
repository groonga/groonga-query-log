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
      def initialize(options)
        @options = options
        @queue = SizedQueue.new(@options.request_queue_size)
        @responses = Queue.new
      end

      def replay(input)
        producer = run_producer(input)
        consumers = run_consumers
        response_logger = run_response_logger
        producer.join
        consumers.each(&:join)
        response_logger.join
      end

      private
      def run_producer(input)
        Thread.new do
          parser = Parser.new
          id = 0
          @options.create_request_output do |output|
            parser.parse(input) do |statistic|
              # TODO: validate orignal_source is one line
              output.puts(statistic.command.original_source)
              @queue.push([id, statistic])
              id += 1
            end
          end
          @options.n_clients.times do
            @queue.push(nil)
          end
        end
      end

      def run_consumers
        @options.n_clients.times.collect do
          Thread.new do
            @options.create_client do |client|
              loop do
                id, statistic = @queue.pop
                if id.nil?
                  @responses.push(nil)
                  break
                end
                replay_command(client, id, statistic.command)
              end
            end
          end
        end
      end

      def replay_command(client, id, command)
        command["cache"] = "no" if @options.disable_cache?
        response = client.execute(command)
        @responses.push(response)
      end

      def run_response_logger
        Thread.new do
          @options.create_responses_output do |output|
            loop do
              response = @responses.pop
              break if response.nil?
              # TODO: ensure response is one line
              # TODO: reorder by ID
              output.puts(response.raw)
            end
          end
        end
      end

      class NullOutput
        class << self
          def open
            output = new
            if block_given?
              yield(output)
            else
              output
            end
          end
        end

        def puts(string)
        end
      end

      class Options
        attr_accessor :host
        attr_accessor :port
        attr_accessor :protocol
        attr_accessor :n_clients
        attr_accessor :request_queue_size
        def initialize
          @host = "127.0.0.1"
          @port = 10041
          @protocol = :gqtp
          @n_clients = 8
          @request_queue_size = 1000
          @disable_cache = false
          @requests_path = nil
          @responses_path = nil
        end

        def create_client(&block)
          Groonga::Client.open(:host     => @host,
                               :port     => @port,
                               :protocol => @protocol,
                               &block)
        end

        def create_request_output(&block)
          if @requests_path
            File.open(@requests_path, "w", &block)
          else
            NullOutput.open(&block)
          end
        end

        def create_responses_output(&block)
          if @responses_path
            File.open(@responses_path, "w", &block)
          else
            NullOutput.open(&block)
          end
        end

        def disable_cache?
          @disable_cache
        end
      end
    end
  end
end
