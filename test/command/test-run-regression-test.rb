# Copyright (C) 2019 Kentaro Hayashi <hayashi@clear-code.com>
# Copyright (C) 2019-2020 Horimoto Yasuhiro <horimoto@clear-code.com>
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
  include Helper::Command
  include Helper::Path

  def setup
    @command = GroongaQueryLog::Command::RunRegressionTest.new
    FileUtils.rm_rf(fixture_path("db.old"))
    FileUtils.rm_rf(fixture_path("db.new"))
    setup_smtp_server
    @n_commands = 238
  end

  def teardown
    teardown_smtp_server
  end

  def setup_smtp_server
    @smtp_host = "127.0.0.1"
    @smtp_port = 20025
    @smtp_request_lines = []
    @now = "Tue, 26 Mar 2019 16:39:46 +0900"
    @smtp_server = TCPServer.open(@smtp_host, @smtp_port)
    @smtp_server_running = true
    @smtp_server_thread = Thread.new do
      while @smtp_server_running
        client = @smtp_server.accept
        client.print("220 localhost SMTP server\r\n")
        client.each_line do |line|
          @smtp_request_lines << line
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
  end

  def teardown_smtp_server
    @smtp_server_running = false
    smtp_client = TCPSocket.new(@smtp_host, @smtp_port)
    smtp_client.write("QUIT\r\n")
    smtp_client.gets
    smtp_client.close
    @smtp_server.close
    @smtp_server_thread.join
  end

  def normalized_smtp_request
    @smtp_request_lines
      .join("")
      .gsub(/^Date: .*\r\n/,
            "Date: #{@now}\r\n")
  end

  def normalize_output(output)
    output
      .gsub(/^\[.*\n/, "")
      .gsub(/^Running.*\n/, "")
      .gsub(/^Elapsed: \d+days \d{2}:\d{2}:\d{2}$/, "Elapsed: 0days 00:00:00")
  end

  def n_executed_commands(output)
    output.slice(/^Number of executed commands:\s+(\d+)/, 1).to_i
  end

  def fixture_path(*components)
    super("run-regression-test", *components)
  end

  def run_command(command_line)
    Dir.chdir(fixture_path) do
      super(@command, command_line)
    end
  end

  def test_success
    success, output = run_command([])
    assert_equal([
                   true,
                   "Elapsed: 0days 00:00:00\n" +
                   "Number of executed commands: #{@n_commands}\n" +
                   "Success\n"
                 ],
                [success, normalize_output(output)])
  end

  def test_reduce_execution_query
    command_line = ["--omit-rate=0.9"]
    _success, output = run_command(command_line)
    assert do
      n_executed_commands(output) < (@n_commands * 0.2)
    end
  end

  def test_mail_from
    success, _output = run_command(["--smtp-server", @smtp_host,
                                    "--smtp-port", @smtp_port.to_s,
                                    "--mail-to", "noreply@example.com",
                                    "--mail-from", "tester@example.com"])
    assert_equal([
                   success,
                   [
                     "From: tester@example.com\r",
                     "From: tester@example.com\r",
                   ],
                 ],
                 [
                   true,
                   normalized_smtp_request.scan(/From: .+/),
                 ])
  end

  sub_test_case("MailNotifier") do
    MailNotifier = GroongaQueryLog::Command::RunRegressionTest::MailNotifier

    def test_started
      options = {
        :smtp_server => @smtp_host,
        :smtp_port => @smtp_port,
        :mail_from => "groonga-query-log@example.com",
        :mail_to => "noreply@example.com",
        :mail_subject_on_start => "Started",
      }
      notifier = MailNotifier.new(options)
      notifier.notify_started
      assert_equal(<<-REQUEST.gsub(/\n/, "\r\n").b, normalized_smtp_request)
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
Subject: Started
Date: #{@now}


.
QUIT
      REQUEST
    end

    def test_success
      options = {
        :smtp_server => @smtp_host,
        :smtp_port => @smtp_port,
        :mail_from => "groonga-query-log@example.com",
        :mail_to => "noreply@example.com",
        :mail_subject_on_success => "Success",
        :mail_subject_on_failure => "Failure",
        :path => fixture_path("mail-notifier/success.log"),
      }
      notifier = MailNotifier.new(options)
      notifier.notify_finished(true, "report")
      assert_equal(<<-REQUEST.gsub(/\n/, "\r\n").b, normalized_smtp_request)
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

report
.
QUIT
      REQUEST
    end

    def test_failure
      options = {
        :smtp_server => @smtp_host,
        :smtp_port => @smtp_port,
        :mail_from => "groonga-query-log@example.com",
        :mail_to => "noreply@example.com",
        :mail_subject_on_success => "Success",
        :mail_subject_on_failure => "Failure",
        :path => fixture_path("mail-notifier/failure.log"),
      }
      notifier = MailNotifier.new(options)
      notifier.notify_finished(false, "report")
      assert_equal(<<-REQUEST.gsub(/\n/, "\r\n").b, normalized_smtp_request)
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
Subject: Failure
Date: #{@now}

report
.
QUIT
      REQUEST
    end
  end
end
