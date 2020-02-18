# Copyright (C) 2013-2018  Kouhei Sutou <kou@clear-code.com>
# Copyright (C) 2020  Horimoto Yasuhiro <horimoto@clear-code.com>
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
require "rubygems/package"

require "groonga-query-log"

module GroongaQueryLog
  module Command
    class VerifyServer
      def initialize
        @options = ServerVerifier::Options.new
      end

      def run(command_line, &callback)
        input_paths = create_parser.parse(command_line)
        same = true
        n_execute_commands = 0
        verifier = ServerVerifier.new(@options)
        if input_paths.empty?
          same = verifier.verify($stdin, &callback)
        else
          input_paths.each do |input_path|
            case input_path
            when /\.tar\.gz\z/
              unless verify_tar_gz(verifier, input_path)
                same = false
                return false if @options.stop_on_failure?
              end
            else
              File.open(input_path) do |input|
                unless verifier.verify(input, &callback)
                  same = false
                  return false if @options.stop_on_failure?
                end
              end
            end
          end
        end
        return same, verifier.n_execute_commands
      end

      private
      def verify_tar_gz(verifier, tar_gz_path, &callback)
        same = true
        Zlib::GzipReader.open(tar_gz_path) do |gzip|
          Gem::Package::TarReader.new(gzip) do |tar|
            tar.each do |entry|
              next unless entry.file?
              unless verifier.verify(StringIO.new(entry.read), &callback)
                same = false
                return false if @options.stop_on_failure?
              end
            end
          end
        end
        same
      end

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

        parser.on("--groonga1-read-timeout=TIMEOUT", Integer,
                  "Timeout on reading response from Groonga server 1.",
                  "You can disable timeout by specifying -1.",
                  "(#{@options.groonga1.read_timeout})") do |timeout|
          @options.groonga1.read_timeout = timeout
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

        parser.on("--groonga2-read-timeout=TIMEOUT", Integer,
                  "Timeout on reading response from Groonga server 2.",
                  "You can disable timeout by specifying -1.",
                  "(#{@options.groonga2.read_timeout})") do |timeout|
          @options.groonga2.read_timeout = timeout
        end

        parser.on("--read-timeout=TIMEOUT", Integer,
                  "Timeout on reading response from both Groonga servers.",
                  "You can disable timeout by specifying -1.") do |timeout|
          @options.groonga1.read_timeout = timeout
          @options.groonga2.read_timeout = timeout
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

        target_command_names_label = @options.target_command_names.join(",")
        parser.on("--target-command-names=NAME1,NAME2,...", Array,
                  "Replay only NAME1,NAME2,... commands",
                  "You can use glob to choose command name",
                  "[#{target_command_names_label}]") do |names|
          @options.target_command_names = names
        end

        parser.on("--no-care-order",
                  "Don't care order of select response records") do
          @options.care_order = false
        end

        parser.on("--output=PATH",
                  "Output results to PATH",
                  "[stdout]") do |path|
          @options.output_path = path
        end

        parser.on("--[no-]verify-cache",
                  "Verify cache for each query.",
                  "[#{@options.verify_cache?}]") do |verify_cache|
          @options.verify_cache = verify_cache
        end

        parser.on("--ignore-drilldown-key=KEY",
                  "Don't compare drilldown result for KEY",
                  "You can specify multiple drilldown keys by",
                  "specifying this option multiple times") do |key|
          @options.ignored_drilldown_keys << key
        end

        parser.on("--[no-]stop-on-failure",
                  "Stop execution on the first failure",
                  "(#{@options.stop_on_failure?})") do |boolean|
          @options.stop_on_failure = boolean
        end

        parser.on("--[no-]rewrite-vector-equal",
                  "Rewrite 'vector == ...' with 'vector @ ...'",
                  "(#{@options.rewrite_vector_equal?})") do |boolean|
          @options.rewrite_vector_equal = boolean
        end

        parser.on("--[no-]rewrite-vector-not-equal-empty-string",
                  "Rewrite 'vector != \"\"' and " +
                  "'vector.column != \"\"' " +
                  "with 'vector_size(vector) > 0'",
                  "(#{@options.rewrite_vector_not_equal_empty_string?})") do |boolean|
          @options.rewrite_vector_not_equal_empty_string = boolean
        end

        parser.on("--vector-accessor=ACCESSOR",
                  "Mark ACCESSOR as rewrite vector targets",
                  "You can specify multiple accessors by",
                  "specifying this option multiple times") do |accessor|
          @options.vector_accessors << accessor
        end

        parser.on("--[no-]rewrite-nullable-reference-number",
                  "Rewrite 'nullable_reference.number' with " +
                  "with '(nullable_reference._key == null ? 0 : " +
                  "nullable_reference.number)'",
                  "(#{@options.rewrite_nullable_reference_number?})") do |boolean|
          @options.rewrite_nullable_reference_number = boolean
        end

        parser.on("--[no-]rewrite-not-or-regular-expression",
                  "Rewrite 'column1 @ \"keyword1\" && column2 @~ " +
                  "\"^(?!.*keyword2|keyword3|...).+$\"' " +
                  "with 'column1 @ \"keyword1\" &! column2 @ \"keyword2\" " +
                  "&! column2 @ \"keyword3\" &! ...'",
                  "(#{@options.rewrite_not_or_regular_expression?})") do |boolean|
          @options.rewrite_not_or_regular_expression = boolean
        end

        parser.on("--[no-]rewrite-and-not-operator",
                  "Rewrite '(column1 @ \"keyword1\") && !(column2 @ " +
                  "\"keyword2\")' " +
                  "with '(column1 @ \"keyword1\") &! (column2 @ " +
                  "\"keyword2\")'",
                  "(#{@options.rewrite_and_not_operator?})") do |boolean|
          @options.rewrite_and_not_operator = boolean
        end

        parser.on("--[no-]debug-rewrite",
                  "Output rewrite logs for debugging",
                  "(#{@options.debug_rewrite?})") do |boolean|
          @options.debug_rewrite = boolean
        end

        parser.on("--omit-rate=RATE", Float,
                  "You can specify rate for omitting execution queries." +
                  "For example, if you specify 0.9 in this option, " +
                  "execute queries with the probability of 1/10.",
                  "(#{@options.omit_rate})") do |rate|
          @options.omit_rate = rate
        end

        parser.on("--nullable-reference-number-accessor=ACCESSOR",
                  "Mark ACCESSOR as rewrite nullable reference number targets",
                  "You can specify multiple accessors by",
                  "specifying this option multiple times") do |accessor|
          @options.nullable_reference_number_accessors << accessor
        end

        create_parser_performance(parser)

        parser.separator("")
        parser.separator("Debug options:")

        parser.on("--abort-on-exception",
                  "Abort on exception in threads") do
          Thread.abort_on_exception = true
        end
      end

      def create_parser_performance(parser)
        parser.separator("")
        parser.separator("Performance options:")

        parser.on("--[no-]verify-performance",
                  "Whether verify performance or not",
                  "[#{@options.verify_performance?}]") do |boolean|
          @options.verify_performance = boolean
        end

        options = @options.performance_verifier_options
        parser.on("--performance-choose-strategy=STRATEGY",
                  options.available_choose_strategies,
                  "How to choose elapsed time",
                  "(#{options.available_choose_strategies.join(", ")})",
                  "[#{options.choose_strategy}]") do |strategy|
          options.choose_strategy = strategy
        end
      end
    end
  end
end
