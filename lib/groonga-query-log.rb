# Copyright (C) 2012-2018  Kouhei Sutou <kou@clear-code.com>
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

require "groonga-log"

require "groonga-query-log/version"
require "groonga-query-log/parser"
require "groonga-query-log/replayer"
require "groonga-query-log/server-verifier"
require "groonga-query-log/command-version-compatibility-checker"

module GroongaQueryLog
  module AnalyzerNamespaceBackwardCompatibility
    def const_missing(name)
      case name
      when :Analyzer
        warn("GroongaQueryLog::Analyzer is deprecated. " +
             "Use GroongaQueryLog::Command::Analyzer instead:\n" +
             caller.join("\n"))
        require "groonga-query-log/command/analyzer"
        const_set(name, Command::Analyzer)
      else
        super
      end
    end
  end

  extend AnalyzerNamespaceBackwardCompatibility
end
