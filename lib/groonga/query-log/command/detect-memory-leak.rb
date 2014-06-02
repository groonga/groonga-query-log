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

require "optparse"

require "groonga/query-log/memory-leak-detector"

module Groonga
  module QueryLog
    module Command
      class DetectMemoryLeak
        def initialize
          @options = MemoryLeakDetector::Options.new
        end

        def run(command_line)
          input_paths = create_parser.parse(command_line)
          detector = MemoryLeakDetector.new(@options)
          input_paths.each do |input_path|
            File.open(input_path) do |input|
              detector.detect(input)
            end
          end
          true
        end

        private
        def create_parser
          parser = OptionParser.new
          parser.version = VERSION
          parser.banner += " QUERY_LOG"

          parser.separator("")
          parser.separator("Options:")

          parser.on("--host=HOST",
                    "Host name or IP address of groonga server",
                    "[#{@options.host}]") do |host|
            @options.host = host
          end

          parser.on("--port=PORT", Integer,
                    "Port number of groonga server",
                    "[#{@options.port}]") do |port|
            @options.port = port
          end

          available_protocols = [:gqtp, :http]
          available_protocols_label = "[#{available_protocols.join(', ')}]"
          parser.on("--protocol=PROTOCOL", available_protocols,
                    "Protocol of groonga server",
                    available_protocols_label) do |protocol|
            @options.protocol = protocol
          end

          parser.on("--pid=PID",
                    "The PID of groonga server",
                    "[#{@options.pid}]") do |pid|
            @options.pid = pid
          end

          parser.on("--n-tries=N", Integer,
                    "The number of the same request tries",
                    "[#{@options.n_tries}]") do |n|
            @options.n_tries = n
          end

          parser.on("--[no-]force-disable-cache",
                    "Force disable cache of select command by cache=no parameter",
                    "[#{@options.force_disable_cache?}]") do |boolean|
            @options.force_disable_cache = boolean
          end
        end
      end
    end
  end
end
