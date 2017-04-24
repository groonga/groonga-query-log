# Copyright (C) 2014-2017  Kouhei Sutou <kou@clear-code.com>
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

require "groonga/query-log"
require "groonga/query-log/command/verify-server"

module Groonga
  module QueryLog
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
          @care_order = true
          @verify_cachehit_mode = false
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
          parser.on("--no-care-order",
                    "Don't care order of select response records") do
            @care_order = false
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

        class GroongaServer
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

            yield
          end

          def ensure_database
            if @options[:recreate_database]
              FileUtils.rm_rf(@database_path.dirname.to_s)
            end

            return if @database_path.exist?
            FileUtils.mkdir_p(@database_path.dirname.to_s)
            system(@groonga, "-n", @database_path.to_s, "quit")
            grn_files.each do |grn_file|
              command = [
                @groonga,
                "--log-path", log_path.to_s,
                "--file", grn_file.to_s,
                @database_path.to_s,
              ]
              command_line = command.join(" ")
              puts("Running...: #{command_line}")
              pid = spawn(*command)
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

          def restart
            self.shutdown
            run_thread = Thread.new do
              self.run{}
            end
            run_thread.join
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

          def grn_files
            files = schema_files
            files += data_files if @options[:load_data]
            files += index_files
            files
          end

          def schema_files
            Pathname.glob("#{@input_directory}/schema/**/*.grn").sort
          end

          def index_files
            Pathname.glob("#{@input_directory}/indexes/**/*.grn").sort
          end

          def data_files
            Pathname.glob("#{@input_directory}/data/**/*.grn").sort
          end
        end

        class Tester
          def initialize(old, new, options)
            @old = old
            @new = new
            @input_directory = options[:input_directory] || Pathname.new(".")
            @working_directory = options[:working_directory] || Pathname.new(".")
            @n_clients = options[:n_clients] || 1
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

            query_log_paths.each do |query_log_path|
              log_path = test_log_path(query_log_path)
              if @options[:skip_finished_queries] and log_path.exist?
                puts("Skip query log: #{query_log_path}")
                next
              else
                puts("Running test against query log...: #{query_log_path}")
              end
              begin
                verify_server(log_path, query_log_path)
              rescue Interrupt
                puts("Interrupt: #{query_log_path}")
              end
              if @new.use_persistent_cache?
                @new.restart
              end
              if @old.use_persistent_cache?
                @old.restart
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

            true
          end

          def verify_server(test_log_path, query_log_path)
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
            command_line << query_log_path.to_s
            if @new.use_persistent_cache? or @old.use_persistent_cache?
              command_line << "--verify-cache"
            end
            verify_server = VerifyServer.new
            verify_server.run(command_line)
          end

          def query_log_paths
            Pathname.glob("#{@input_directory}/query-logs/**/*.log").sort
          end

          def test_log_path(query_log_path)
            @working_directory + "results" + query_log_path.basename
          end
        end
      end
    end
  end
end
