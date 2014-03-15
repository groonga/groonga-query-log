# -*- coding: utf-8 -*-
#
# Copyright (C) 2013-2014  Kouhei Sutou <kou@clear-code.com>
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

require "groonga/query-log/parser"
require "groonga/query-log/response-comparer"

module Groonga
  module QueryLog
    class ServerVerifier
      def initialize(options)
        @options = options
        @queue = SizedQueue.new(@options.request_queue_size)
        @different_results = Queue.new
      end

      def verify(input)
        producer = run_producer(input)
        consumers = run_consumers
        reporter = run_reporter
        producer.join
        consumers.each(&:join)
        @different_results.push(nil)
        reporter.join
      end

      private
      def run_producer(input)
        Thread.new do
          parser = Parser.new
          parser.parse(input) do |statistic|
            next unless target_command?(statistic.command)
            @queue.push(statistic)
          end
          @options.n_clients.times do
            @queue.push(nil)
          end
        end
      end

      def run_consumers
        @options.n_clients.times.collect do
          Thread.new do
            begin
              loop do
                break if run_consumer
              end
            rescue Groonga::Client::Error
              log_client_error($!)
            end
          end
        end
      end

      def run_consumer
        @options.groonga1.create_client do |groonga1_client|
          @options.groonga2.create_client do |groonga2_client|
            loop do
              statistic = @queue.pop
              return true if statistic.nil?
              begin
                verify_command(groonga1_client, groonga2_client,
                               statistic.command)
              rescue Groonga::Client::Error
                log_client_error($!) do
                  $stderr.puts(statistic.command.original_source)
                end
                return false
              end
            end
          end
        end
      end

      def run_reporter
        Thread.new do
          @options.create_output do |output|
            loop do
              result = @different_results.pop
              break if result.nil?
              report_result(output, result)
            end
          end
        end
      end

      def target_command?(command)
        @options.target_command_name?(command.name)
      end

      def verify_command(groonga1_client, groonga2_client, command)
        command["cache"] = "no" if @options.disable_cache?
        response1 = groonga1_client.execute(command)
        response2 = groonga2_client.execute(command)
        comparer = ResponseComparer.new(command, response1.body, response2.body)
        unless comparer.same?
          @different_results.push([command, response1, response2])
        end
      end

      def report_result(output, result)
        command, response1, response2 = result
        output.puts("command: #{command.original_source}")
        output.puts("response1: #{response1.body}")
        output.puts("response2: #{response2.body}")
      end

      def log_client_error(error)
        $stderr.puts(Time.now.iso8601)
        yield if block_given?
        if error.respond_to?(:raw_error)
          target_error = error.raw_error
        else
          target_error = error
        end
        $stderr.puts("#{target_error.class}: #{target_error.message}")
        $stderr.puts(target_error.backtrace)
      end

      class Options
        attr_reader :groonga1
        attr_reader :groonga2
        attr_accessor :n_clients
        attr_writer :request_queue_size
        attr_writer :disable_cache
        attr_accessor :target_command_names
        attr_accessor :output_path
        def initialize
          @groonga1 = GroongaOptions.new
          @groonga2 = GroongaOptions.new
          @n_clients = 8
          @request_queue_size = nil
          @disable_cache = false
          @output_path = nil
          @target_command_names = ["select"]
        end

        def request_queue_size
          @request_queue_size || @n_clients * 3
        end

        def disable_cache?
          @disable_cache
        end

        def target_command_name?(name)
          @target_command_names.any? do |name_pattern|
            flags = 0
            flags |= File::FNM_EXTGLOB if File.const_defined?(:FNM_EXTGLOB)
            File.fnmatch(name_pattern, name, flags)
          end
        end

        def create_output(&block)
          if @output_path
            File.open(@output_path, "w", &block)
          else
            yield($stdout)
          end
        end
      end

      class GroongaOptions
        attr_accessor :host
        attr_accessor :port
        attr_accessor :protocol
        def initialize
          @host     = "127.0.0.1"
          @port     = 10041
          @protocol = :gqtp
        end

        def create_client(&block)
          Groonga::Client.open(:host     => @host,
                               :port     => @port,
                               :protocol => @protocol,
                               &block)
        end
      end
    end
  end
end
