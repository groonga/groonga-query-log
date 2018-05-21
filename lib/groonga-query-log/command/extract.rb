# Copyright (C) 2011-2018  Kouhei Sutou <kou@clear-code.com>
# Copyright (C) 2012  Haruka Yoshihara <yoshihara@clear-code.com>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License version 2.1 as published by the Free Software Foundation.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

require "ostruct"
require "optparse"
require "pathname"

require "groonga-query-log"
require "groonga-query-log/command-line"

module GroongaQueryLog
    module Command
      class Extract < CommandLine
        attr_accessor :options
        attr_reader :option_parser

        def initialize
          @options = nil
          @option_parser = nil
          setup_options
        end

        # Executes extractor for Groonga's query logs.
        # "groonga-query-log-extract" command runs this method.
        #
        # @example
        #   extractor = GroongaQueryLog::Command::Extract.new
        #   extractor.run("--output", "commands.output",
        #                 "--command", "select",
        #                 "query.log")
        #
        # If only paths of query log files are specified,
        # this method prints command(s) of them to console.
        #
        # @param [Array<String>] arguments arguments for
        #   groonga-query-log-extract. Please execute
        #   "groonga-query-log-extract --help" or see #setup_options.
        def run(arguments)
          begin
            log_paths = @option_parser.parse!(arguments)
          rescue OptionParser::ParseError
            $stderr.puts($!.message)
            return false
          end

          begin
            if @options.output_path
              File.open(@options.output_path, "w") do |output|
                extract(log_paths, output)
              end
            else
              extract(log_paths, $stdout)
            end
          rescue Interrupt
          rescue Error
            $stderr.puts($!.message)
            return false
          end

          true
        end

        private
        def setup_options
          @options = OpenStruct.new
          @options.unify_format = nil
          @options.commands = []
          @options.exclude_commands = []
          @options.include_arguments = true
          @options.output_path = nil
          @option_parser = OptionParser.new do |parser|
            parser.version = VERSION
            parser.banner += " QUERY_LOG1 ..."

            available_formats = ["uri", "command"]
            parser.on("--unify-format=FORMAT",
                      available_formats,
                      "Unify command format to FORMAT.",
                      "(#{available_formats.join(', ')})",
                      "[not unify]") do |format|
              @options.unify_format = format
            end

            parser.on("--command=COMMAND",
                      "Extract only COMMAND.",
                      "To extract one or more commands,",
                      "specify this command a number of times.",
                      "Use /.../ as COMMAND to match command with regular expression.",
                      "[all commands]") do |command|
              case command
              when /\A\/(.*)\/(i)?\z/
                @options.commands << Regexp.new($1, $2 == "i")
              when
                @options.commands << command
              end
            end

            parser.on("--exclude-command=COMMAND",
                      "Don't extract COMMAND.",
                      "To ignore one or more commands,",
                      "specify this command a number of times.",
                      "Use /.../ as COMMAND to match command with regular expression.",
                      "[no commands]") do |command|
              case command
              when /\A\/(.*)\/(i)?\z/
                @options.exclude_commands << Regexp.new($1, $2 == "i")
              when
                @options.exclude_commands << command
              end
            end

            parser.on("--[no-]include-arguments",
                      "Whether include command arguments",
                      "[#{@options.include_arguments}]") do |include_arguments|
              @options.include_arguments = include_arguments
            end

            parser.on("--output=PATH",
                      "Output to PATH.",
                      "[standard output]") do |path|
              @options.output_path = path
            end
          end
        end

        def extract(log_paths, output)
          parser = Parser.new
          parse_log(parser, log_paths) do |statistic|
            extract_command(statistic, output)
          end
        end

        def extract_command(statistic, output)
          command = statistic.command
          return unless target?(command)
          unless @options.include_arguments
            command.arguments.clear
          end
          command_text = nil
          case @options.unify_format
          when "uri"
            command_text = command.to_uri_format
          when "command"
            command_text = command.to_command_format
          else
            command_text = command.to_s
          end
          output.puts(command_text)
        end

        def target?(command)
          name = command.command_name
          target_commands = @options.commands
          exclude_commands = @options.exclude_commands

          unless target_commands.empty?
            return target_commands.any? {|target_command| target_command === name}
          end

          unless exclude_commands.empty?
            return (not exclude_commands.any? {|exclude_command| exclude_command === name})
          end

          true
        end
      end
    end
end
