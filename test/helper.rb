# Copyright (C) 2011-2025  Sutou Kouhei <kou@clear-code.com>
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

require "stringio"

require "groonga/command"

require "groonga-query-log"

module Helper
  module Path
    def fixture_path(*components)
      File.join(File.dirname(__FILE__), "fixtures", *components)
    end
  end

  module Command
    def require_tty
      omit("Require tty") unless $stdin.tty?
    end

    def open_error_output
      Tempfile.open("groonga-query-log.error") do |error|
        error.sync = true
        original_stderr = $stderr.dup
        $stderr.reopen(error)
        begin
          yield(error)
        ensure
          $stderr.reopen(original_stderr)
        end
      end
    end

    def run_command(command, command_line)
      stdout = $stdout.dup
      output = Tempfile.open("output")
      success = false
      begin
        $stdout.reopen(output)
        success = command.run(command_line)
      ensure
        $stdout.reopen(stdout)
      end
      output.close
      output.open
      [success, output.read]
    end
  end
end
