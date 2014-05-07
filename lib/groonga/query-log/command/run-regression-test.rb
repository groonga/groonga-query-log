# Copyright (C) 2014  Kouhei Sutou <kou@clear-code.com>
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

          @new_groonga = "groonga"
          @new_database = "db.new/db"

          @load_data = true
          @run_queries = true
        end

        def run(*command_line)
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

          parser.separator("")
          parser.separator("Old Groonga:")
          parser.on("--old-groonga=GROONGA",
                    "Old groonga command",
                    "(#{@old_groonga})") do |groonga|
            @old_groonga = groonga
          end

          parser.separator("")
          parser.separator("New Groonga:")
          parser.on("--new-groonga=GROONGA",
                    "New groonga command",
                    "(#{@new_groonga})") do |groonga|
            @new_groonga = groonga
          end

          parser.separator("")
          parser.separator("Operations:")
          parser.on("--no-load-data",
                    "Don't load data. Just loads schema to Groonga database") do
            @load_data = false
          end
          parser.on("--no-run-queries",
                    "Don't run queries. Just creates Groonga database") do
            @run_queries = false
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
            :load_data   => @load_data,
            :run_queries => @run_queries,
          }
          directory_options.merge(options)
        end

        def tester_options
          directory_options
        end

        def old_groonga_server
          GroongaServer.new(@old_groonga,
                            @old_database,
                            server_options)
        end

        def new_groonga_server
          GroongaServer.new(@new_groonga,
                            @new_database,
                            server_options)
        end

        class GroongaServer
          attr_reader :host, :port
          def initialize(groonga, database_path, options)
            @input_directory = options[:input_directory] || Pathname.new(".")
            @working_directory = options[:working_directory] || Pathname.new(".")
            @groonga = groonga
            @database_path = @working_directory + database_path
            @host = "127.0.0.1"
            @port = find_unused_port
            @options = options
          end

          def run
            ensure_database
            return unless @options[:run_queries]

            @pid = spawn(@groonga,
                         "--bind-address", @host,
                         "--port", @port.to_s,
                         "--log-path", log_path.to_s,
                         "--query-log-path", query_log_path.to_s,
                         "--protocol", "http",
                         "-s",
                         @database_path.to_s)

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

          def ensure_database
            return if @database_path.exist?
            FileUtils.mkdir_p(@database_path.dirname.to_s)
            system(@groonga, "-n", @database_path.to_s, "quit")
            grn_files.each do |grn_file|
              command = [@groonga, @database_path.to_s]
              command_line = "#{command.join(' ')} < #{grn_file}"
              puts("Running...: #{command_line}")
              pid = spawn(*command, :in => grn_file.to_s)
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

          def send_command(name)
            Net::HTTP.start(@host, @port) do |http|
              response = http.get("/d/#{name}")
              response.body
            end
          end

          def grn_files
            files = schema_files
            files += data_files if @options[:load_data]
            files
          end

          def schema_files
            Pathname.glob("#{@input_directory}/schema/**/*.grn").sort
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
            @options = options
            @n_ready_waits = 2
            @clone_pids = []
          end

          def run
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

            old_thread.join
            new_thread.join
          end

          private
          def run_test
            @n_ready_waits -= 1
            return unless @n_ready_waits.zero?

            @clone_pids.each do |pid|
              Process.waitpid(pid)
            end

            query_log_paths.each do |query_log_path|
              query_log_key = query_log_path.basename(".*").to_s
              query_log_key = query_log_key.gsub(/\Aquery-/, "")
              test_log_base_name = "test-result-#{query_log_key}.log"
              test_log_path = @working_directory + test_log_base_name
              if test_log_path.exist?
                puts("Skip query log: #{query_log_path}")
                next
              else
                puts("Running test against query log...: #{query_log_path}")
              end
              pid = fork do
                verify_server(test_log_path, query_log_path)
                exit!
              end
              begin
                Process.waitpid(pid)
              rescue Interrupt
                Process.kill(:TERM, pid)
                Process.waitpid(pid)
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
              "--n-clients=1",
              "--groonga1-host=#{@old.host}",
              "--groonga1-port=#{@old.port}",
              "--groonga1-protocol=http",
              "--groonga2-host=#{@new.host}",
              "--groonga2-port=#{@new.port}",
              "--groonga2-protocol=http",
              "--target-command-name=select",
              "--output", test_log_path.to_s,
              "--abort-on-exception",
              query_log_path.to_s,
            ]
            verify_serer = VerifyServer.new
            verify_serer.run(*command_line)
          end

          def query_log_paths
            Pathname.glob("#{@input_directory}/query-logs/**/*.log").sort
          end
        end
      end
    end
  end
end
