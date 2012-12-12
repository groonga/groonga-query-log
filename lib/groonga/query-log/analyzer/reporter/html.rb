# -*- coding: utf-8 -*-
#
# Copyright (C) 2011-2012  Kouhei Sutou <kou@clear-code.com>
# Copyright (C) 2012  Haruka Yoshihara <yoshihara@clear-code.com>
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

require "erb"
require "groonga/query-log/analyzer/reporter"

module Groonga
  module QueryLog
    class Analyzer
      class HTMLReporter < Reporter
        include ERB::Util

        def report_statistic(statistic)
          write(",") if @index > 0
          write("\n")
          write(format_statistic(statistic))
          @index += 1
        end

        def start
          write(header)
        end

        def finish
          write(footer)
        end

        def report_summary
          summary_html = erb(<<-EOH, __LINE__ + 1, binding)
        <h2>Summary</h2>
        <div class="summary">
    <%= analyze_parameters %>
    <%= metrics %>
    <%= slow_operations %>
        </div>
          EOH
          write(summary_html)
        end

        def report_statistics
          write(statistics_header)
          super
          write(statistics_footer)
        end

        def report_statistic(statistic)
          command = statistic.command
          statistic_html = erb(<<-EOH, __LINE__ + 1, binding)
          <div class="statistic-heading">
            <h3>Command</h3>
            <div class="metrics">
              [<%= format_time(statistic.start_time) %>
               -
               <%= format_time(statistic.last_time) %>
               (<%= format_elapsed(statistic.elapsed_in_seconds,
                                   :slow? => statistic.slow?) %>)]
              (<%= span({:class => "return-code"}, h(statistic.return_code)) %>)
            </div>
            <%= div({:class => "raw-command"}, h(statistic.raw_command)) %>
          </div>
          <div class="statistic-parameters">
            <h3>Parameters</h3>
            <dl>
              <dt>name</dt>
              <dd><%= h(command.name) %></dd>
    <% command.arguments.each do |key, value| %>
              <dt><%= h(key) %></dt>
              <dd><%= h(value) %></dd>
    <% end %>
             </dl>
          </div>
          <div class="statistic-operations">
            <h3>Operations</h3>
            <ol>
    <% statistic.each_operation do |operation| %>
              <li>
                <%= format_elapsed(operation[:relative_elapsed_in_seconds],
                                   :slow? => operation[:slow?]) %>:
                <%= span({:class => "name"}, h(operation[:name])) %>:
                <%= span({:class => "context"}, h(operation[:context])) %>
              </li>
    <% end %>
            </ol>
          </div>
          EOH
          write(statistic_html)
        end

        private
        def erb(content, line, _binding=nil)
          _erb = ERB.new(content, nil, "<>")
          eval(_erb.src, _binding || binding, __FILE__, line)
        end

        def header
          erb(<<-EOH, __LINE__ + 1)
    <html>
      <head>
        <title>groonga query analyzer</title>
        <style>
    table,
    table tr,
    table tr th,
    table tr td
    {
      border: 1px solid black;
    }

    span.slow
    {
      color: red;
    }

    div.parameters
    {
      float: left;
      padding: 2em;
    }

    div.parameters h3
    {
      text-align: center;
    }

    div.parameters table
    {
      margin-right: auto;
      margin-left: auto;
    }

    div.statistics
    {
      clear: both;
    }

    td.elapsed,
    td.ratio,
    td.n
    {
      text-align: right;
    }

    td.name
    {
      text-align: center;
    }
        </style>
      </head>
      <body>
        <h1>groonga query analyzer</h1>
          EOH
        end

        def footer
          erb(<<-EOH, __LINE__ + 1)
      </body>
    </html>
          EOH
        end

        def statistics_header
          erb(<<-EOH, __LINE__ + 1)
        <h2>Slow Queries</h2>
        <div>
          EOH
        end

        def statistics_footer
          erb(<<-EOH, __LINE__ + 1)
        </div>
          EOH
        end

        def analyze_parameters
          erb(<<-EOH, __LINE__ + 1)
          <div class="parameters">
            <h3>Analyze Parameters</h3>
            <table>
              <tr><th>Name</th><th>Value</th></tr>
              <tr>
                <th>Slow response threshold</th>
                <td><%= h(@statistics.slow_response_threshold) %>sec</td>
              </tr>
              <tr>
                <th>Slow operation threshold</th>
                <td><%= h(@statistics.slow_operation_threshold) %>sec</td>
              </tr>
            </table>
          </div>
          EOH
        end

        def metrics
          erb(<<-EOH, __LINE__ + 1)
          <div class="parameters">
            <h3>Metrics</h3>
            <table>
              <tr><th>Name</th><th>Value</th></tr>
              <tr>
                <th># of responses</th>
                <td><%= h(@statistics.n_responses) %></td>
              </tr>
              <tr>
                <th># of slow responses</th>
                <td><%= h(@statistics.n_slow_responses) %></td>
              </tr>
              <tr>
                <th>responses/sec</th>
                <td><%= h(@statistics.responses_per_second) %></td>
              </tr>
              <tr>
                <th>start time</th>
                <td><%= format_time(@statistics.start_time) %></td>
              </tr>
              <tr>
                <th>last time</th>
                <td><%= format_time(@statistics.last_time) %></td>
              </tr>
              <tr>
                <th>period</th>
                <td><%= h(@statistics.period) %>sec</td>
              </tr>
              <tr>
                <th>slow response ratio</th>
                <td><%= h(@statistics.slow_response_ratio) %>%</td>
              </tr>
              <tr>
                <th>total response time</th>
                <td><%= h(@statistics.total_elapsed) %>sec</td>
              </tr>
            </table>
          </div>
          EOH
        end

        def slow_operations
          erb(<<-EOH, __LINE__ + 1)
          <div class="statistics">
            <h3>Slow Operations</h3>
            <table class="slow-operations">
              <tr>
                <th>total elapsed(sec)</th>
                <th>total elapsed(%)</th>
                <th># of operations</th>
                <th># of operations(%)</th>
                <th>operation name</th>
                <th>context</th>
              </tr>
    <% @statistics.each_slow_operation do |grouped_operation| %>
              <tr>
                <td class="elapsed">
                  <%= format_elapsed(grouped_operation[:total_elapsed]) %>
                </td>
                <td class="ratio">
                  <%= format_ratio(grouped_operation[:total_elapsed_ratio]) %>
                </td>
                <td class="n">
                  <%= h(grouped_operation[:n_operations]) %>
                </td>
                <td class="ratio">
                  <%= format_ratio(grouped_operation[:n_operations_ratio]) %>
                </td>
                <td class="name"><%= h(grouped_operation[:name]) %></td>
                <td class="context">
                  <%= format_context(grouped_operation[:context]) %>
                </td>
              </tr>
    <% end %>
            </table>
          </div>
          EOH
        end

        def format_time(time)
          span({:class => "time"}, h(super))
        end

        def format_elapsed(elapsed, options={})
          formatted_elapsed = span({:class => "elapsed"}, h("%8.8f" % elapsed))
          if options[:slow?]
            formatted_elapsed = span({:class => "slow"}, formatted_elapsed)
          end
          formatted_elapsed
        end

        def format_ratio(ratio)
          h("%5.2f%%" % ratio)
        end

        def format_context(context)
          h(context).gsub(/,/, ",<wbr />")
        end

        def tag(name, attributes, content)
          html = "<#{name}"
          html_attributes = attributes.collect do |key, value|
            "#{h(key)}=\"#{h(value)}\""
          end
          html << " #{html_attributes.join(' ')}" unless attributes.empty?
          html << ">"
          html << content
          html << "</#{name}>"
          html
        end

        def span(attributes, content)
          tag("span", attributes, content)
        end

        def div(attributes, content)
          tag("div", attributes, content)
        end
      end
    end
  end
end
