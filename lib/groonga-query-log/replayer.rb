# Copyright (C) 2013-2020  Sutou Kouhei <kou@clear-code.com>
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

require "time"
require "thread"

require "groonga/client"

require "groonga-query-log/parser"

module GroongaQueryLog
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
            next if statistic.command.nil?
            next unless target_command?(statistic.command)
            # TODO: validate orignal_source is one line
            output.puts(statistic.command.original_source)
            if @options.output_type
              statistic.command[:output_type] ||= @options.output_type
            end
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
          loop do
            break if run_consumer
          end
        end
      end
    end

    def run_consumer
      @options.create_client do |client|
        loop do
          id, statistic = @queue.pop
          if id.nil?
            @responses.push(nil)
            return true
          end
          begin
            replay_command(client, id, statistic.command)
          rescue Groonga::Client::Error
            # TODO: add error log mechanism
            $stderr.puts(Time.now.iso8601(6))
            $stderr.puts(statistic.command.original_source)
            $stderr.puts($!.raw_error.message)
            $stderr.puts($!.raw_error.backtrace)
            return false
          rescue
            # TODO: add error log mechanism
            $stderr.puts(Time.now.iso8601(6))
            $stderr.puts(statistic.command.original_source)
            $stderr.puts($!.message)
            $stderr.puts($!.backtrace)
            return false
          end
        end
      end
    end

    def replay_command(client, id, command)
      command["cache"] = "no" if @options.disable_cache?
      response = client.execute(command)
      case command.output_type
      when :json, :xml, :tsv
        response.raw << "\n" unless response.raw.end_with?("\n")
      end
      @responses.push(response)
    end

    def run_response_logger
      Thread.new do
        @options.create_responses_output do |output|
          loop do
            response = @responses.pop
            break if response.nil?
            # TODO: reorder by ID
            output.print(response.raw)
          end
        end
      end
    end

    def target_command?(command)
      @options.target_command_name?(command.command_name)
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

      def print(string)
      end
    end

    class Options
      attr_accessor :host
      attr_accessor :port
      attr_accessor :protocol
      attr_accessor :read_timeout
      attr_accessor :n_clients
      attr_writer :request_queue_size
      attr_writer :disable_cache
      attr_accessor :target_command_names
      attr_accessor :requests_path
      attr_accessor :responses_path
      attr_accessor :output_type
      def initialize
        @host = "127.0.0.1"
        @port = 10041
        @protocol = :http
        @read_timeout = Groonga::Client::Default::READ_TIMEOUT
        @n_clients = 8
        @request_queue_size = nil
        @disable_cache = false
        @target_command_names = []
        @requests_path = nil
        @responses_path = nil
        @output_type = nil
      end

      def create_client(&block)
        Groonga::Client.open(:host     => @host,
                             :port     => @port,
                             :protocol => @protocol,
                             :read_timeout => @read_timeout,
                             &block)
      end

      def create_request_output(&block)
        case @requests_path
        when nil
          NullOutput.open(&block)
        when "-"
          yield($stdout)
          File.open(@requests_path, "w", &block)
        end
      end

      def create_responses_output(&block)
        case @responses_path
        when nil
          NullOutput.open(&block)
        when "-"
          yield($stdout)
        else
          File.open(@responses_path, "w", &block)
        end
      end

      def request_queue_size
        @request_queue_size || @n_clients * 3
      end

      def disable_cache?
        @disable_cache
      end

      def target_command_name?(name)
        return true if @target_command_names.empty?
        @target_command_names.any? do |name_pattern|
          flags = 0
          flags |= File::FNM_EXTGLOB if File.const_defined?(:FNM_EXTGLOB)
          File.fnmatch(name_pattern, name, flags)
        end
      end
    end
  end
end
