# Copyright (C) 2014-2018  Kouhei Sutou <kou@clear-code.com>
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

require "rbconfig"
require "optparse"
require "socket"
require "fileutils"
require "pathname"
require "net/http"

require "groonga-query-log"
require "groonga-query-log/command/verify-server"

module GroongaQueryLog
  module Command
    class RunRegressionTest
      def initialize
        @input_directory = Pathname.new(".")
        @working_directory = Pathname.new(".")

        @old_groonga = "groonga"
        @old_database = "db.old/db"
        @old_groonga_options = []

        @new_groonga = "groonga"
        @new_database = "db.new/db"
        @new_groonga_options = []

        @recreate_database = false
        @load_data = true
        @run_queries = true
        @skip_finished_queries = false
        @output_query_log = false
        @stop_on_failure = false
        @rewrite_vector_equal = false
        @rewrite_vector_not_equal_empty_string = false
        @vector_accessors = []
        @rewrite_nullable_reference_number = false
        @nullable_reference_number_accessors = []
        @rewrite_regular_expression = false

        @care_order = true
        @ignored_drilldown_keys = []
        @target_command_names = ServerVerifier::Options.new.target_command_names

        @read_timeout = Groonga::Client::Default::READ_TIMEOUT
      end

      def run(command_line)
        option_parser = create_option_parser
        begin
          option_parser.parse!(command_line)
        rescue OptionParser::ParseError => error
          $stderr.puts(error.message)
          return false
        end

        tester = Tester.new(old_groonga_server,
                            new_groonga_server,
                            tester_options)
        tester.run
      end

      private
      def create_option_parser
        parser = OptionParser.new
        parser.version = VERSION

        parser.separator("")
        parser.separator("Path:")
        parser.on("--input-directory=DIRECTORY",
                  "Load schema and data from DIRECTORY.",
                  "(#{@input_directory})") do |directory|
          @input_directory = Pathname.new(directory)
        end
        parser.on("--working-directory=DIRECTORY",
                  "Use DIRECTORY as working directory.",
                  "(#{@working_directory})") do |directory|
          @working_directory = Pathname.new(directory)
        end

        parser.separator("")
        parser.separator("Throughput:")
        parser.on("--n-clients=N", Integer,
                  "Use N clients concurrently.",
                  "(#{@n_clients})") do |n|
          @n_clients = n
        end

        parser.separator("")
        parser.separator("Old Groonga:")
        parser.on("--old-groonga=GROONGA",
                  "Old groonga command",
                  "(#{@old_groonga})") do |groonga|
          @old_groonga = groonga
        end

        parser.on("--old-groonga-option=OPTION",
                  "Add an additional old groonga option",
                  "You can specify this option multiple times to specify multiple groonga options",
                  "(no options)") do |groonga_option|
          @old_groonga_options << groonga_option
        end

        parser.separator("")
        parser.separator("New Groonga:")
        parser.on("--new-groonga=GROONGA",
                  "New groonga command",
                  "(#{@new_groonga})") do |groonga|
          @new_groonga = groonga
        end

        parser.on("--new-groonga-option=OPTION",
                  "Add an additional new groonga option",
                  "You can specify this option multiple times to specify multiple groonga options",
                  "(no options)") do |groonga_option|
          @new_groonga_options << groonga_option
        end

        parser.separator("")
        parser.separator("Operations:")
        parser.on("--recreate-database",
                  "Always recreate Groonga database") do
          @recreate_database = true
        end
        parser.on("--no-load-data",
                  "Don't load data. Just loads schema to Groonga database") do
          @load_data = false
        end
        parser.on("--no-run-queries",
                  "Don't run queries. Just creates Groonga database") do
          @run_queries = false
        end
        parser.on("--skip-finished-queries",
                  "Don't run finished query logs.") do
          @skip_finished_queries = true
        end
        parser.on("--output-query-log",
                  "Output query log in verified target Groonga servers") do
          @output_query_log = true
        end
        parser.on("--[no-]stop-on-failure",
                  "Stop execution on the first failure",
                  "(#{@stop_on_failure})") do |boolean|
          @stop_on_failure = boolean
        end
        parser.on("--[no-]rewrite-vector-equal",
                  "Rewrite 'vector == ...' with 'vector @ ...'",
                  "(#{@rewrite_vector_equal})") do |boolean|
          @rewrite_vector_equal = boolean
        end
        parser.on("--[no-]rewrite-vector-not-equal-empty-string",
                  "Rewrite 'vector != \"\"' and " +
                  "'vector.column != \"\"' " +
                  "with 'vector_size(vector) > 0'",
                  "(#{@rewrite_vector_not_equal_empty_string})") do |boolean|
          @rewrite_vector_not_equal_empty_string = boolean
        end
        parser.on("--vector-accessor=ACCESSOR",
                  "Mark ACCESSOR as rewrite vector targets",
                  "You can specify multiple vector accessors by",
                  "specifying this option multiple times") do |accessor|
          @vector_accessors << accessor
        end
        parser.on("--[no-]rewrite-nullable-reference-number",
                  "Rewrite 'nullable_reference.number' with " +
                  "with '(nullable_reference._key == null ? 0 : " +
                  "nullable_reference.number)'",
                  "(#{@rewrite_nullable_reference_number})") do |boolean|
          @rewrite_nullable_reference_number = boolean
        end
        parser.on("--nullable-reference-number-accessor=ACCESSOR",
                  "Mark ACCESSOR as rewrite nullable reference number targets",
                  "You can specify multiple accessors by",
                  "specifying this option multiple times") do |accessor|
          @nullable_reference_number_accessors << accessor
        end
        parser.on("--[no-]rewrite_regular_expression",
                  "Rewrite 'column1 @ \"keyword\" && column2 @~ " +
                  "\"^(?!.*keyword1|keyword2|...).+$\"' " +
                  "with 'column1 @ \"keyword\" &! column2 @ \"keyword1\" " +
                  "&! column2 @ \"keyword2\" &! ...'",
                  "(#{@rewrite_regular_expression})") do |boolean|
          @rewrite_regular_expression = boolean
        end

        parser.separator("")
        parser.separator("Comparisons:")
        parser.on("--no-care-order",
                  "Don't care order of select response records") do
          @care_order = false
        end
        parser.on("--ignore-drilldown-key=KEY",
                  "Don't compare drilldown result for KEY",
                  "You can specify multiple drilldown keys by",
                  "specifying this option multiple times") do |key|
          @ignored_drilldown_keys << key
        end
        target_command_names_label = @target_command_names.join(",")
        parser.on("--target-command-names=NAME1,NAME2,...", Array,
                  "Test only NAME1,NAME2,... commands",
                  "You can use glob to choose command name",
                  "[#{target_command_names_label}]") do |names|
          @target_command_names = names
        end

        parser.separator("")
        parser.separator("Network:")
        parser.on("--read-timeout=TIMEOUT", Integer,
                  "Timeout on reading response from Groonga servers.",
                  "You can disable timeout by specifying -1.",
                  "[#{@read_timeout}]") do |timeout|
          @read_timeout = timeout
        end

        parser
      end

      def directory_options
        {
          :input_directory   => @input_directory,
          :working_directory => @working_directory,
        }
      end

      def server_options
        options = {
          :load_data             => @load_data,
          :run_queries           => @run_queries,
          :recreate_database     => @recreate_database,
          :output_query_log      => @output_query_log,
        }
        directory_options.merge(options)
      end

      def tester_options
        options = {
          :n_clients  => @n_clients,
          :care_order => @care_order,
          :skip_finished_queries => @skip_finished_queries,
          :ignored_drilldown_keys => @ignored_drilldown_keys,
          :stop_on_failure => @stop_on_failure,
          :rewrite_vector_equal => @rewrite_vector_equal,
          :rewrite_vector_not_equal_empty_string =>
            @rewrite_vector_not_equal_empty_string,
          :vector_accessors => @vector_accessors,
          :rewrite_nullable_reference_number =>
            @rewrite_nullable_reference_number,
          :nullable_reference_number_accessors =>
            @nullable_reference_number_accessors,
          :rewrite_regular_expression =>
            @rewrite_regular_expression,
          :target_command_names => @target_command_names,
          :read_timeout => @read_timeout,
        }
        directory_options.merge(options)
      end

      def old_groonga_server
        GroongaServer.new(@old_groonga,
                          @old_groonga_options,
                          @old_database,
                          server_options)
      end

      def new_groonga_server
        GroongaServer.new(@new_groonga,
                          @new_groonga_options,
                          @new_database,
                          server_options)
      end

      module Loggable
        def puts(*args)
          $stdout.puts(*args)
          $stdout.flush
        end
      end

      class GroongaServer
        include Loggable

        attr_reader :host, :port
        def initialize(groonga, groonga_options, database_path, options)
          @input_directory = options[:input_directory] || Pathname.new(".")
          @working_directory = options[:working_directory] || Pathname.new(".")
          @groonga = groonga
          @groonga_options = groonga_options
          @database_path = @working_directory + database_path
          @host = "127.0.0.1"
          @port = find_unused_port
          @options = options
        end

        def run
          return unless @options[:run_queries]

          arguments = @groonga_options.dup
          arguments.concat(["--bind-address", @host])
          arguments.concat(["--port", @port.to_s])
          arguments.concat(["--protocol", "http"])
          arguments.concat(["--log-path", log_path.to_s])
          if @options[:output_query_log]
            arguments.concat(["--query-log-path", query_log_path.to_s])
          end
          arguments << "-s"
          arguments << @database_path.to_s
          @pid = spawn(@groonga, *arguments)

          n_retries = 10
          begin
            send_command("status")
          rescue SystemCallError
            sleep(1)
            n_retries -= 1
            raise if n_retries.zero?
            retry
          end

          yield if block_given?
        end

        def ensure_database
          if @options[:recreate_database]
            FileUtils.rm_rf(@database_path.dirname.to_s)
          end

          return if @database_path.exist?
          FileUtils.mkdir_p(@database_path.dirname.to_s)
          system(@groonga, "-n", @database_path.to_s, "quit")
          load_files.each do |load_file|
            if load_file.extname == ".rb"
              env = {
                "GROONGA_LOG_PATH" => log_path.to_s,
              }
              command = [
                RbConfig.ruby,
                load_file.to_s,
                @database_path.to_s,
              ]
            else
              env = {}
              command = [
                @groonga,
                "--log-path", log_path.to_s,
                "--file", load_file.to_s,
                @database_path.to_s,
              ]
            end
            command_line = command.join(" ")
            puts("Running...: #{command_line}")
            pid = spawn(env, *command)
            begin
              pid, status = Process.waitpid2(pid)
            rescue Interrupt
              Process.kill(:TERM, pid)
              pid, status = Process.waitpid2(pid)
            end
            unless status.success?
              raise "Failed to run: #{command_line}"
            end
          end
        end

        def use_persistent_cache?
          @groonga_options.include?("--cache-base-path")
        end

        def shutdown
          begin
            send_command("shutdown")
          rescue SystemCallError
          end
          Process.waitpid(@pid)
        end

        private
        def find_unused_port
          server = TCPServer.new(@host, 0)
          begin
            server.addr[1]
          ensure
            server.close
          end
        end

        def log_path
          @database_path.dirname + "groonga.log"
        end

        def query_log_path
          @database_path.dirname + "query.log"
        end

        def send_command(name)
          Net::HTTP.start(@host, @port) do |http|
            response = http.get("/d/#{name}")
            response.body
          end
        end

        def load_files
          files = schema_files
          files += data_files if @options[:load_data]
          files += index_files
          files
        end

        def schema_files
          Pathname.glob("#{@input_directory}/schema/**/*.{grn,rb}").sort
        end

        def index_files
          Pathname.glob("#{@input_directory}/indexes/**/*.{grn,rb}").sort
        end

        def data_files
          Pathname.glob("#{@input_directory}/data/**/*.{grn,rb}").sort
        end
      end

      class Tester
        include Loggable

        def initialize(old, new, options)
          @old = old
          @new = new
          @input_directory = options[:input_directory] || Pathname.new(".")
          @working_directory = options[:working_directory] || Pathname.new(".")
          @n_clients = options[:n_clients] || 1
          @stop_on_failure = options[:stop_on_failure]
          @options = options
          @n_ready_waits = 2
        end

        def run
          @old.ensure_database
          @new.ensure_database

          old_thread = Thread.new do
            @old.run do
              run_test
            end
          end
          new_thread = Thread.new do
            @new.run do
              run_test
            end
          end

          old_thread_success = old_thread.value
          new_thread_success = new_thread.value

          old_thread_success and new_thread_success
        end

        private
        def run_test
          @n_ready_waits -= 1
          return true unless @n_ready_waits.zero?

          same = true
          query_log_paths.each do |query_log_path|
            log_path = test_log_path(query_log_path)
            if @options[:skip_finished_queries] and log_path.exist?
              puts("Skip query log: #{query_log_path}")
              next
            else
              puts("Running test against query log...: #{query_log_path}")
            end
            begin
              if use_persistent_cache?
                callback = lambda do
                  if @old.use_persistent_cache?
                    @old.shutdown
                    @old.run
                  end
                  if @new.use_persistent_cache?
                    @new.shutdown
                    @new.run
                  end
                end
              else
                callback = nil
              end
              unless verify_server(log_path, query_log_path, &callback)
                same = false
                break if @stop_on_failure
              end
            rescue Interrupt
              puts("Interrupt: #{query_log_path}")
            end
          end

          old_thread = Thread.new do
            @old.shutdown
          end
          new_thread = Thread.new do
            @new.shutdown
          end
          old_thread.join
          new_thread.join

          same
        end

        def verify_server(test_log_path, query_log_path, &callback)
          command_line = [
            "--n-clients=#{@n_clients}",
            "--groonga1-host=#{@old.host}",
            "--groonga1-port=#{@old.port}",
            "--groonga1-protocol=http",
            "--groonga2-host=#{@new.host}",
            "--groonga2-port=#{@new.port}",
            "--groonga2-protocol=http",
            "--output", test_log_path.to_s,
          ]
          command_line << "--no-care-order" if @options[:care_order] == false
          @options[:ignored_drilldown_keys].each do |key|
            command_line.concat(["--ignore-drilldown-key", key])
          end
          command_line << query_log_path.to_s
          if use_persistent_cache?
            command_line << "--verify-cache"
          end
          if @stop_on_failure
            command_line << "--stop-on-failure"
          end
          if @options[:rewrite_vector_equal]
            command_line << "--rewrite-vector-equal"
          end
          if @options[:rewrite_vector_not_equal_empty_string]
            command_line << "--rewrite-vector-not-equal-empty-string"
          end
          accessors = @options[:vector_accessors] || []
          accessors.each do |accessor|
            command_line << "--vector-accessor"
            command_line << accessor
          end
          if @options[:rewrite_nullable_reference_number]
            command_line << "--rewrite-nullable-reference-number"
          end
          accessors = @options[:nullable_reference_number_accessors] || []
          accessors.each do |accessor|
            command_line << "--nullable-reference-number-accessor"
            command_line << accessor
          end
          if @options[:rewrite_regular_expression]
            command_line << "--rewrite_regular_expression"
          end
          if @options[:target_command_names]
            command_line << "--target-command-names"
            command_line << @options[:target_command_names].join(",")
          end
          if @options[:read_timeout]
            command_line << "--read-timeout"
            command_line << @options[:read_timeout].to_s
          end
          verify_server = VerifyServer.new
          verify_server.run(command_line, &callback)
        end

        def query_log_paths
          Pathname.glob("#{@input_directory}/query-logs/**/*.{log,tar.gz}").sort
        end

        def test_log_path(query_log_path)
          @working_directory + "results" + "#{query_log_path.basename}.log"
        end

        def use_persistent_cache?
          @old.use_persistent_cache? or @new.use_persistent_cache?
        end
      end
    end
  end
end
