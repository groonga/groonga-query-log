# Copyright (C) 2012-2017  Haruka Yoshihara <yoshihara@clear-code.com>
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
    module CommandLineUtils
      def log_via_stdin?
        stdin_with_pipe? or stdin_with_redirect?
      end

      def stdin_with_pipe?
        File.pipe?($stdin)
      end

      def stdin_with_redirect?
        not File.select([$stdin], [], [], 0).nil?
      end
    end
end
