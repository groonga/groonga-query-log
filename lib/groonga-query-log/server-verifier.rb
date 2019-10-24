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
require "groonga-query-log/performance-verifier"
require "groonga-query-log/response-comparer"

module GroongaQueryLog
  class ServerVerifier
    def initialize(options)
      @options = options
      @queue = SizedQueue.new(@options.request_queue_size)
      @events = Queue.new
    end

    def verify(input, &callback)
      @same = true
      @slow = false
      @client_error_is_occurred = false
      producer = run_producer(input, &callback)
      reporter = run_reporter
      producer.join
      @events.push(nil)
      reporter.join
      success?
    end

    private
    def run_producer(input, &callback)
      Thread.new do
        consumers = run_consumers

        parser = Parser.new
        n_commands = 0
        callback_per_n_commands = 100
        parser.parse(input) do |statistic|
          break if stop?

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
            next if stop?

            original_source = statistic.command.original_source
            begin
              verify_command(groonga1_client, groonga2_client,
                             statistic.command)
            rescue => error
              log_client_error(error) do
                $stderr.puts(original_source)
              end
              @client_error_is_occurred = true
              @events.push([:error, statistic.command, error])
              return false
            end
            if @options.verify_cache?
              command = Groonga::Command::Status.new
              begin
                verify_command(groonga1_client, groonga2_client,
                               command)
              rescue => error
                log_client_error(error) do
                  $stderr.puts("status after #{original_source}")
                end
                @client_error_is_occurred = true
                @events.push([:error, command, error])
                return false
              end
            end
          end
        end
      end
    end

    def run_reporter
      Thread.new do
        @options.open_output do |output|
          loop do
            event = @events.pop
            break if event.nil?
            case event[0]
            when :different
              report_different(output, *event[1..-1])
            when :slow
              report_slow(output, *event[1..-1])
            when :error
              report_error(output, *event[1..-1])
            end
          end
        end
      end
    end

    def target_command?(command)
      @options.target_command_name?(command.command_name)
    end

    def success?
      return false unless @same
      return false if @slow
      return false if @client_error_is_occurred
      true
    end

    def failed?
      not success?
    end

    def stop?
      @options.stop_on_failure? and failed?
    end

    def verify_command(groonga1_client, groonga2_client, command)
      command["cache"] = "no" if @options.disable_cache?
      command["cache"] = "no" if @options.verify_performance?
      command["output_type"] = "json"
      rewrite_filter(command, "filter")
      rewrite_filter(command, "scorer")
      response1 = groonga1_client.execute(command)
      response2 = groonga2_client.execute(command)
      compare_options = {
        :care_order => @options.care_order,
        :ignored_drilldown_keys => @options.ignored_drilldown_keys,
      }
      comparer = ResponseComparer.new(command, response1, response2,
                                      compare_options)
      unless comparer.same?
        @same = false
        @events.push([:different, command, response1, response2])
        return
      end

      return unless @options.verify_performance?
      responses1 = [response1]
      responses2 = [response2]
      n_tries = 4
      n_tries.times do
        responses1 << groonga1_client.execute(command)
        responses2 << groonga2_client.execute(command)
      end
      verifier = PerformanceVerifier.new(command,
                                         responses1,
                                         responses2,
                                         @options.performance_verifier_options)
      if verifier.slow?
        @slow = true
        @events.push([:slow,
                      command,
                      verifier.old_elapsed_time,
                      verifier.new_elapsed_time])
      end
    end

    def rewrite_filter(command, name)
      target = command[name]
      return if target.nil?
      return unless @options.need_filter_rewrite?

      rewriter = FilterRewriter.new(target, @options.to_filter_rewriter_options)
      rewritten_target = rewriter.rewrite
      return if target == rewritten_target

      $stderr.puts("Rewritten #{name}")
      $stderr.puts("  Before: #{target}")
      $stderr.puts("   After: #{rewritten_target}")
      command[name] = rewritten_target
    end

    def report_different(output, command, response1, response2)
      command_source = command.original_source || command.to_uri_format
      output.puts("command: #{command_source}")
      output.puts("response1: #{response1.body.to_json}")
      output.puts("response2: #{response2.body.to_json}")
      output.flush
    end

    def report_slow(output, command, old_elapsed_time, new_elapsed_time)
      command_source = command.original_source || command.to_uri_format
      output.puts("command: #{command_source}")
      output.puts("elapsed_time_old: #{old_elapsed_time}")
      output.puts("elapsed_time_new: #{new_elapsed_time}")
      output.puts("elapsed_time_ratio: #{new_elapsed_time / old_elapsed_time}")
      output.flush
    end

    def report_error(output, command, error)
      command_source = command.original_source || command.to_uri_format
      output.puts("command: #{command_source}")
      error.backtrace.reverse_each do |trace|
        output.puts("backtrace: #{trace}")
      end
      output.puts("error: #{error.class}: #{error.message}")
      output.flush
    end

    def log_client_error(error)
      $stderr.puts(Time.now.iso8601(6))
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
      attr_writer :rewrite_vector_not_equal_empty_string
      attr_accessor :vector_accessors
      attr_writer :rewrite_nullable_reference_number
      attr_accessor :nullable_reference_number_accessors
      attr_writer :rewrite_not_or_regular_expression
      attr_writer :rewrite_and_not_operator
      attr_writer :verify_performance
      attr_reader :performance_verifier_options
      def initialize
        @groonga1 = GroongaOptions.new
        @groonga2 = GroongaOptions.new
        @n_clients = 8
        @request_queue_size = nil
        @disable_cache = false
        @output_path = nil
        @output_opened = false
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
        @rewrite_vector_not_equal_empty_string = false
        @vector_accessors = []
        @rewrite_nullable_reference_number = false
        @nullable_reference_number_accessors = []
        @rewrite_not_or_regular_expression = false
        @rewrite_and_not_operator = false
        @verify_performance = false
        @performance_verifier_options = PerformanceVerifier::Options.new
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

      def rewrite_vector_not_equal_empty_string?
        @rewrite_vector_not_equal_empty_string
      end

      def rewrite_nullable_reference_number?
        @rewrite_nullable_reference_number
      end

      def rewrite_not_or_regular_expression?
        @rewrite_not_or_regular_expression
      end

      def rewrite_and_not_operator?
        @rewrite_and_not_operator
      end

      def target_command_name?(name)
        return false if name.nil?

        @target_command_names.any? do |name_pattern|
          flags = 0
          flags |= File::FNM_EXTGLOB if File.const_defined?(:FNM_EXTGLOB)
          File.fnmatch(name_pattern, name, flags)
        end
      end

      def open_output(&block)
        if @output_path
          if @output_opened
            mode = "a"
          else
            FileUtils.mkdir_p(File.dirname(@output_path))
            mode = "w"
            @output_opened = true
          end
          File.open(@output_path, mode, &block)
        else
          yield($stdout)
        end
      end

      def need_filter_rewrite?
        rewrite_vector_equal? or
          rewrite_vector_not_equal_empty_string? or
          rewrite_nullable_reference_number? or
          rewrite_not_or_regular_expression? or
          rewrite_and_not_operator?
      end

      def to_filter_rewriter_options
        {
          :rewrite_vector_equal => rewrite_vector_equal?,
          :rewrite_vector_not_equal_empty_string =>
            rewrite_vector_not_equal_empty_string?,
          :vector_accessors => vector_accessors,
          :rewrite_nullable_reference_number =>
            rewrite_nullable_reference_number?,
          :nullable_reference_number_accessors =>
            nullable_reference_number_accessors,
          :rewrite_not_or_regular_expression =>
            rewrite_not_or_regular_expression?,
          :rewrite_and_not_operator =>
            rewrite_and_not_operator?,
        }
      end

      def verify_performance?
        @verify_performance
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
