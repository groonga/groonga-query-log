# Copyright (C) 2012  Haruka Yoshihara <yoshihara@clear-code.com>
# Copyright (C) 2017-2019  Sutou Kouhei <kou@clear-code.com>
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

module GroongaQueryLog
  class CommandLine
    class Error < StandardError
    end

    class NoInputError < Error
    end

    private
    def parse_log(parser, log_paths, &process_statistic)
      return to_enum(__method__, parser, log_paths) unless block_given?
      if log_paths.empty?
        if stdin_with_pipe? or stdin_with_redirect?
          parser.parse($stdin, &process_statistic)
        else
          raise NoInputError, "Error: Please specify input log files."
        end
      else
        parser.parse_paths(log_paths, &process_statistic)
      end
    end

    def stdin_with_pipe?
      File.pipe?($stdin)
    end

    def stdin_with_redirect?
      not File.select([$stdin], [], [], 0).nil?
    end
  end
end
