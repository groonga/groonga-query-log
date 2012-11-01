# -*- coding: utf-8 -*-
#
# Copyright (C) 2011-2012  Kouhei Sutou <kou@clear-code.com>
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

require "English"
require "shellwords"
require "cgi"

module Groonga
  module QueryLog
    class Command
      class << self
        @@registered_commands = {}
        def register(name, klass)
          @@registered_commands[name] = klass
        end

        def parse(input)
          if input.start_with?("/d/")
            parse_uri_path(input)
          else
            parse_command_line(input)
          end
        end

        private
        def parse_uri_path(path)
          name, parameters_string = path.split(/\?/, 2)
          parameters = {}
          if parameters_string
            parameters_string.split(/&/).each do |parameter_string|
              key, value = parameter_string.split(/\=/, 2)
              parameters[key] = CGI.unescape(value)
            end
          end
          name = name.gsub(/\A\/d\//, '')
          name, output_type = name.split(/\./, 2)
          parameters["output_type"] = output_type if output_type
          command_class = @@registered_commands[name] || self
          command = command_class.new(name, parameters)
          command.original_format = :uri
          command
        end

        def parse_command_line(command_line)
          name, *options = Shellwords.shellwords(command_line)
          parameters = {}
          options.each_slice(2) do |key, value|
            parameters[key.gsub(/\A--/, '')] = value
          end
          command_class = @@registered_commands[name] || self
          command = command_class.new(name, parameters)
          command.original_format = :command
          command
        end
      end

      attr_reader :name, :parameters
      attr_accessor :original_format
      def initialize(name, parameters)
        @name = name
        @parameters = parameters
        @original_format = nil
      end

      def ==(other)
        other.is_a?(self.class) and
          @name == other.name and
          @parameters == other.parameters
      end

      def uri_format?
        @original_format == :uri
      end

      def command_format?
        @original_format == :command
      end

      def to_uri_format
        path = "/d/#{@name}"
        parameters = @parameters.dup
        output_type = parameters.delete("output_type")
        path << ".#{output_type}" if output_type
        unless parameters.empty?
          sorted_parameters = parameters.sort_by do |name, _|
            name.to_s
          end
          uri_parameters = sorted_parameters.collect do |name, value|
            "#{CGI.escape(name)}=#{CGI.escape(value)}"
          end
          path << "?"
          path << uri_parameters.join("&")
        end
        path
      end

      def to_command_format
        command_line = [@name]
        sorted_parameters = @parameters.sort_by do |name, _|
          name.to_s
        end
        sorted_parameters.each do |name, value|
          escaped_value = value.gsub(/[\n"\\]/) do
            special_character = $MATCH
            case special_character
            when "\n"
              "\\n"
            else
              "\\#{special_character}"
            end
          end
          command_line << "--#{name}"
          command_line << "\"#{escaped_value}\""
        end
        command_line.join(" ")
      end
    end

    class SelectCommand < Command
      register("select", self)

      def sortby
        @parameters["sortby"]
      end

      def scorer
        @parameters["scorer"]
      end

      def query
        @parameters["query"]
      end

      def filter
        @parameters["filter"]
      end

      def conditions
        @conditions ||= filter.split(/(?:&&|&!|\|\|)/).collect do |condition|
          condition = condition.strip
          condition = condition.gsub(/\A[\s\(]*/, '')
          condition = condition.gsub(/[\s\)]*\z/, '') unless /\(/ =~ condition
          condition
        end
      end

      def drilldowns
        @drilldowns ||= (@parameters["drilldown"] || "").split(/\s*,\s*/)
      end

      def output_columns
        @parameters["output_columns"]
      end
    end
  end
end
