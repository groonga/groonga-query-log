# Copyright (C) 2013-2018  Kouhei Sutou <kou@clear-code.com>
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

require "groonga-query-log/filter-rewriter"
require "groonga-query-log/parser"
require "groonga-query-log/response-comparer"

module GroongaQueryLog
  class ServerVerifier
    def initialize(options)
      @options = options
      @queue = SizedQueue.new(@options.request_queue_size)
      @different_results = Queue.new
    end

    def verify(input, &callback)
      @same = true
      producer = run_producer(input, &callback)
      reporter = run_reporter
      producer.join
      @different_results.push(nil)
      reporter.join
      @same
    end

    private
    def run_producer(input, &callback)
      Thread.new do
        consumers = run_consumers

        parser = Parser.new
        n_commands = 0
        callback_per_n_commands = 100
        parser.parse(input) do |statistic|
          break if !@same and @options.stop_on_failure?

          command = statistic.command
          next if command.nil?
          next unless target_command?(command)
          n_commands += 1
          @queue.push(statistic)

          if callback and (n_commands % callback_per_n_commands).zero?
            @options.n_clients.times do
              @queue.push(nil)
            end
            consumers.each(&:join)
            callback.call
            consumers = run_consumers
          end
        end
        @options.n_clients.times do
          @queue.push(nil)
        end
        consumers.each(&:join)
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
      @options.groonga1.create_client do |groonga1_client|
        @options.groonga2.create_client do |groonga2_client|
          loop do
            statistic = @queue.pop
            return true if statistic.nil?

            original_source = statistic.command.original_source
            begin
              verify_command(groonga1_client, groonga2_client,
                             statistic.command)
            rescue
              log_client_error($!) do
                $stderr.puts(original_source)
              end
              return false
            end
            if @options.verify_cache?
              begin
                verify_command(groonga1_client, groonga2_client,
                               Groonga::Command::Status.new)
              rescue
                log_client_error($!) do
                  $stderr.puts("status after #{original_source}")
                end
                return false
              end
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
      @options.target_command_name?(command.command_name)
    end

    def verify_command(groonga1_client, groonga2_client, command)
      command["cache"] = "no" if @options.disable_cache?
      command["output_type"] = "json"
      filter = command["filter"]
      if filter and @options.need_filter_rewrite?
        rewriter = FilterRewriter.new(filter,
                                      @options.to_filter_rewriter_options)
        command["filter"] = rewriter.rewrite
      end
      response1 = groonga1_client.execute(command)
      response2 = groonga2_client.execute(command)
      compare_options = {
        :care_order => @options.care_order,
        :ignored_drilldown_keys => @options.ignored_drilldown_keys,
      }
      comparer = ResponseComparer.new(command, response1, response2,
                                      compare_options)
      unless comparer.same?
        @different_results.push([command, response1, response2])
      end
    end

    def report_result(output, result)
      @same = false
      command, response1, response2 = result
      command_source = command.original_source || command.to_uri_format
      output.puts("command: #{command_source}")
      output.puts("response1: #{response1.body.to_json}")
      output.puts("response2: #{response2.body.to_json}")
      output.flush
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
      attr_accessor :care_order
      attr_writer :verify_cache
      attr_accessor :ignored_drilldown_keys
      attr_writer :stop_on_failure
      attr_writer :rewrite_vector_equal
      attr_accessor :vector_accessors
      def initialize
        @groonga1 = GroongaOptions.new
        @groonga2 = GroongaOptions.new
        @n_clients = 8
        @request_queue_size = nil
        @disable_cache = false
        @output_path = nil
        @target_command_names = [
          "io_flush",
          "logical_count",
          "logical_range_filter",
          "logical_shard_list",
          "logical_select",
          "normalize",
          "object_exist",
          "select",
          "status",
        ]
        @care_order = true
        @verify_cache = false
        @ignored_drilldown_keys = []
        @stop_on_failure = false
        @rewrite_vector_equal = false
        @vector_accessors = []
      end

      def request_queue_size
        @request_queue_size || @n_clients * 3
      end

      def disable_cache?
        @disable_cache
      end

      def verify_cache?
        @verify_cache
      end

      def stop_on_failure?
        @stop_on_failure
      end

      def rewrite_vector_equal?
        @rewrite_vector_equal
      end

      def target_command_name?(name)
        return false if name.nil?

        @target_command_names.any? do |name_pattern|
          flags = 0
          flags |= File::FNM_EXTGLOB if File.const_defined?(:FNM_EXTGLOB)
          File.fnmatch(name_pattern, name, flags)
        end
      end

      def create_output(&block)
        if @output_path
          FileUtils.mkdir_p(File.dirname(@output_path))
          File.open(@output_path, "w", &block)
        else
          yield($stdout)
        end
      end

      def need_filter_rewrite?
        rewrite_vector_equal?
      end

      def to_filter_rewriter_options
        {
          :rewrite_vector_equal => rewrite_vector_equal?,
          :vector_accessors => vector_accessors,
        }
      end
    end

    class GroongaOptions
      attr_accessor :host
      attr_accessor :port
      attr_accessor :protocol
      attr_accessor :read_timeout
      def initialize
        @host         = "127.0.0.1"
        @port         = 10041
        @protocol     = :gqtp
        @read_timeout = Groonga::Client::Default::READ_TIMEOUT
      end

      def create_client(&block)
        Groonga::Client.open(:host         => @host,
                             :port         => @port,
                             :protocol     => @protocol,
                             :read_timeout => @read_timeout,
                             &block)
      end
    end
  end
end
