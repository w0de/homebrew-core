#
# Author:: Harry Seeber (<git@sysop.ooo>)
# Cookbook:: homebrew-core
# Recipes:: formula
#
# Copyright (c) 2021-present Harry Seeber
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# See ../files/Formula/README.md for usage.

return unless macos? && Homebrew.exists?

tap = ::File.join(Homebrew.taps, "homebrew/homebrew-cask/Formula")

previous = if ::File.exists?(Homebrew.formula_cache)
  Chef::JSONCompat.parse(::File.read(Homebrew.formula_cache))
else
  []
end

defined = run_context.cookbook_collection["homebrew-core"].manifest_records_by_path.map do |path, _|
  ::File.basename(path).gsub(".rb", "") if /files\/Formula\/[@\d\.\-\w]*\.rb/.match?(path)
end.compact

managed = defined.uniq & (node["homebrew-core"]["custom-formulae"] || []).uniq
removed = previous - managed

Chef::Log.debug("[homebrew-core::formula] found cookbook files: #{defined}") if defined.any?
Chef::Log.info("[homebrew-core::formula] creating new shims for #{managed}") if managed.any?
Chef::Log.info("[homebrew-core::formula] deleting old shims for #{removed}") if removed.any?

removed.each do |formula|
  file ::File.join(tap, "#{formula}.rb") do
    ignore_failure true
    action :delete
  end
end

file Homebrew.formula_cache do
  owner "root"
  group "wheel"
  content Chef::JSONCompat.to_json_pretty(managed.sort)
  action managed.any? ? :create : :delete
end

execute "#{Homebrew.bin} tap homebrew/cask" do
  user Homebrew.owner
  login true
  ignore_failure true
  only_if { managed.any? }
end

directory tap do
  owner Homebrew.owner
  group "admin"
  recursive true
  only_if { managed.any? }
end

managed.each do |formula|
  cookbook_file ::File.join(tap, "#{formula}.rb") do
    source "Formula/#{formula}.rb"
    owner Homebrew.owner
    group "admin"
  end
end
