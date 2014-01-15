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

require "optparse"

require "groonga/query-log"

module Groonga
  module QueryLog
    module Command
      class VerifyServer
        def initialize
          @options = ServerVerifier::Options.new
        end

        def run(*command_line)
          input_paths = create_parser.parse(*command_line)
          verifier = ServerVerifier.new(@options)
          if input_paths.empty?
            verifier.verify($stdin)
          else
            input_paths.each do |input_path|
              File.open(input_path) do |input|
                verifier.verify(input)
              end
            end
          end
        end

        private
        def create_parser
          parser = OptionParser.new
          parser.version = VERSION
          parser.banner += " QUERY_LOG1 QUERY_LOG2 ..."

          parser.separator("")
          parser.separator("Options:")

          available_protocols = [:gqtp, :http]
          available_protocols_label = "[#{available_protocols.join(', ')}]"

          parser.on("--groonga1-host=HOST",
                    "Host name or IP address of Groonga server 1",
                    "[#{@options.groonga1.host}]") do |host|
            @options.groonga1.host = host
          end

          parser.on("--groonga1-port=PORT", Integer,
                    "Port number of Groonga server 1",
                    "[#{@options.groonga1.port}]") do |port|
            @options.groonga1.port = port
          end

          parser.on("--groonga1-protocol=PROTOCOL", available_protocols,
                    "Protocol of Groonga server 1",
                    available_protocols_label) do |protocol|
            @options.groonga1.protocol = protocol
          end

          parser.on("--groonga2-host=HOST",
                    "Host name or IP address of Groonga server 2",
                    "[#{@options.groonga2.host}]") do |host|
            @options.groonga2.host = host
          end

          parser.on("--groonga2-port=PORT", Integer,
                    "Port number of Groonga server 2",
                    "[#{@options.groonga2.port}]") do |port|
            @options.groonga2.port = port
          end

          parser.on("--groonga2-protocol=PROTOCOL", available_protocols,
                    "Protocol of Groonga server 2",
                    available_protocols_label) do |protocol|
            @options.groonga2.protocol = protocol
          end

          parser.on("--n-clients=N", Integer,
                    "The max number of concurrency",
                    "[#{@options.n_clients}]") do |n_clients|
            @options.n_clients = n_clients
          end

          parser.on("--request-queue-size=SIZE", Integer,
                    "The size of request queue",
                    "[auto]") do |size|
            @options.request_queue_size = size
          end

          parser.on("--disable-cache",
                    "Add 'cache=no' parameter to request",
                    "[#{@options.disable_cache?}]") do
            @options.disable_cache = true
          end

          parser.on("--target-command-name=NAME",
                    "Add NAME to target command names",
                    "You can specify this option zero or more times",
                    "See also --target-command-names") do |name|
            @options.target_command_names << name
          end

          target_command_names_label = @options.target_command_names.join(", ")
          parser.on("--target-command-names=NAME1,NAME2,...", Array,
                    "Replay only NAME1,NAME2,... commands",
                    "You can use glob to choose command name",
                    "[#{target_command_names_label}]") do |names|
            @options.target_command_names = names
          end

          parser.on("--output=PATH",
                    "Output results to PATH",
                    "[stdout]") do |path|
            @options.output_path = path
          end

          parser.separator("Debug options:")
          parser.separator("")

          parser.on("--abort-on-exception",
                    "Abort on exception in threads") do
            Thread.abort_on_excepption = true
          end
        end
      end
    end
  end
end
