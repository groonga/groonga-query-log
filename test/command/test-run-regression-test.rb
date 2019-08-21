# coding: utf-8
# Copyright (C) 2019 Kentaro Hayashi <hayashi@clear-code.com>
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

require "groonga-query-log/command/run-regression-test"

class RunRegressionTestCommandTest < Test::Unit::TestCase
  include Helper::Path

  def fixture_path(*components)
    super("regression-test-logs", *components)
  end

  class SMTPServer
    def initialize
      @socket = TCPServer.open(host, port)
    end
  end

  sub_test_case("MailNotifier") do
    MailNotifier = GroongaQueryLog::Command::RunRegressionTest::MailNotifier

    def setup
      @smtp_host = "127.0.0.1"
      @smtp_port = 20025
      @requests = []
      @now = "Tue, 26 Mar 2019 16:39:46 +0900"
      @server = TCPServer.open(@smtp_host, @smtp_port)
      @thread = Thread.new do
        client = @server.accept
        client.print("220 localhost SMTP server\r\n")
        client.each_line do |line|
          @requests << line
          case line.chomp
          when /\AEHLO /
            client.print("250 AUTH\r\n")
          when /\AMAIL FROM:/
            client.print("250 2.1.0 Ok\r\n")
          when /\ARCPT TO:/
            client.print("250 2.1.0 Ok\r\n")
          when "DATA"
            client.print("354 End data with <CR><LF>.<CR><LF>\r\n")
          when "."
            client.print("250 2.0.0 Ok\r\n")
          when "QUIT"
            client.print("221 2.0.0 Bye\r\n")
            client.close
            break
          end
        end
      end
    end

    def teardown
      @server.close
      @thread.kill
    end

    def normalized_request
      @requests
        .join("")
        .gsub(/^Date: .*\r\n/,
              "Date: #{@now}\r\n")
    end

    def test_success
      options = {
        :smtp_server => @smtp_host,
        :smtp_port => @smtp_port,
        :mail_from => "groonga-query-log@example.com",
        :mail_to => "noreply@example.com",
        :mail_subject_on_success => "Success",
        :mail_subject_on_failure => "Failure",
        :path => fixture_path("results"),
      }
      notifier = MailNotifier.new(true, 3000, options)
      notifier.notify
      assert_equal(<<-REQUEST.gsub(/\n/, "\r\n").b, normalized_request)
EHLO 127.0.0.1
MAIL FROM:<#{options[:mail_from]}>
RCPT TO:<#{options[:mail_to]}>
DATA
MIME-Version: 1.0
X-Mailer: groonga-query-log test reporter #{GroongaQueryLog::VERSION};
  https://github.com/groonga/groonga-query-log
Content-Type: text/plain; charset=utf-8
Content-Transfer-Encoding: 8bit
From: #{options[:mail_from]}
To: #{options[:mail_to]}
Subject: Success
Date: #{@now}

Elapsed: 0days 00:50:00
Report:
Command:
/d/select?table=Logs&match_columns=message&query=%E7%84%BC%E8%82%89
Name: select
Arguments:
  match_columns: message
  query: 焼肉
  table: Logs
--- old
+++ new
@@ -1,4 +1,4 @@
 [[[2],
   [["_id", "UInt32"], ["message", "Text"]],
   [1, "log message1: 焼肉"],
-  [2, "log message2: 焼肉"]]]
+  [3, "log message3: 焼肉"]]]

.
QUIT
      REQUEST
    end
  end
end
