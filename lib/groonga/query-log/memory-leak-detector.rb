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

require "groonga/client"

require "groonga/query-log/parser"

module Groonga
  module QueryLog
    class MemoryLeakDetector
      def initialize(options)
        @options = options
      end

      def detect(input)
        each_command(input) do |command|
          command["cache"] = "no"
          @options.create_client do |client|
            previous_memory_usage = nil
            @options.n_tries.times do |i|
              client.execute(command)
              previous_memory_usage = current_memory_usage
              current_memory_usage = memory_usage
              next if previous_memory_usage.nil?
              if previous_memory_usage != current_memory_usage
                max_n_digits = [
                  compute_n_digits(previous_memory_usage),
                  compute_n_digits(current_memory_usage),
                ].max
                puts("detect a memory leak:")
                puts("Nth try: #{i}")
                puts("previous: %*d" % [max_n_digits, previous_memory_usage])
                puts(" current: %*d" % [max_n_digits, current_memory_usage])
                puts(command.original_source)
              end
            end
          rescue Groonga::Client::Connection::Error
            # TODO: add error log mechanism
            $stderr.puts(Time.now.iso8601)
            $stderr.puts(statistic.command.original_source)
            $stderr.puts($!.raw_error.message)
            $stderr.puts($!.raw_error.backtrace)
          end
        end
      end

      private
      def each_command(input)
        parser = Parser.new
        parser.parse(input) do |statistic|
          yield(statistic.command)
        end
      end

      def memory_usage
        `ps -o rss --no-header --pid #{@options.pid}`.to_i
      end

      def compute_n_digits(n)
        (Math.log10(n) + 1).floor
      end

      class Options
        attr_accessor :host
        attr_accessor :port
        attr_accessor :protocol
        attr_accessor :pid
        attr_accessor :n_tries
        def initialize
          @host = "127.0.0.1"
          @port = 10041
          @protocol = :gqtp
          @pid = guess_groonga_server_pid
          @n_tries = 10
        end

        def create_client(&block)
          Groonga::Client.open(:host     => @host,
                               :port     => @port,
                               :protocol => @protocol,
                               &block)
        end

        private
        def guess_groonga_server_pid
          # This command line works only for ps by procps.
          pid = `ps -o pid --no-header -C groonga`.strip
          if pid.empty?
            nil
          else
            pid.to_i
          end
        end
      end
    end
  end
end
