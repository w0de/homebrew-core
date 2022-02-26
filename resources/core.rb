#
# Author:: Harry Seeber (<git@sysop.ooo>)
# Cookbook:: homebrew-core
# Resources:: homebrew_core
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

unified_mode true
provides :homebrew_core, os: "darwin"

property :owner, String, default: lazy { Homebrew.owner }
property :analytics, [TrueClass, FalseClass, NilClass], default: nil
property :xcode_cli_tools, [TrueClass, FalseClass], default: true
property :brew_update_frequency, Integer, default: 86400
property :force, [TrueClass, FalseClass], default: false
property :standard_packages, Array, default: []

action_class do
  def can_install?
    !(Homebrew.emulated_chef? || node["homebrew-core"]["install"]["url"].nil? || \
      node["homebrew-core"]["disallowed-owners"].include?(new_resource.owner))
  end

  def can_uninstall?
    !(Homebrew.emulated_chef? || node["homebrew-core"]["uninstall"]["url"].nil?)
  end

  def do_filesystem_permissions
    return if Homebrew.arm64?

    intel_prefix = "/usr/local"
    # https://github.com/Homebrew/brew/blob/master/Library/Homebrew/keg.rb
    zsh_dirs = %w[share/zsh share/zsh/site-functions]
    dirs = %w[bin etc include lib sbin share var opt
              share/zsh share/zsh/site-functions
              var/homebrew var/homebrew/linked
              Cellar Caskroom Homebrew Frameworks
              bin etc include lib sbin share opt var
              Frameworks etc/bash_completion.d lib/pkgconfig
              share/aclocal share/doc share/info share/locale share/man
              share/man/man1 share/man/man2 share/man/man3 share/man/man4
              share/man/man5 share/man/man6 share/man/man7 share/man/man8
              var/log var/homebrew var/homebrew/linked]

    (dirs + zsh_dirs).uniq.each do |path|
      directory ::File.join(intel_prefix, path) do
        action :create
        group Homebrew.group
        owner new_resource.owner
        mode zsh_dirs.include?(path) ? '0755' : '0775'
        ignore_failure true
        only_if { ::Dir.exists?(path) }
      end
    end
  end

  def do_install
    sh = "#{Chef::Config[:file_cache_path]}/homebrew_install.sh"
    sudo "chef-homebrew_core-brew-install" do
      user new_resource.owner
      commands [sh, "/bin/chmod", "/bin/mkdir", "/usr/sbin/chown", "/usr/bin/chgrp"]
      nopasswd true
      action :create
      notifies :delete, "sudo[chef-homebrew_core-brew-install]", :delayed
      notifies(
        :upgrade,
        "build_essential[homebrew_core install xcode Command Line Tools]",
        :before
      )
    end

    remote_file "homebrew's install.sh" do
      path sh
      source node["homebrew"]["install"]["url"]
      checksum node["homebrew"]["install"]["checksum"]
      owner new_resource.owner
      group Homebrew.group
      mode "0700"
      retries 2
    end

    execute "homebrew's install.sh" do
      command sh
      environment lazy { { "HOME" => ::Dir.home(new_resource.owner), "USER" => new_resource.owner } }
      user new_resource.owner
      login true
      notifies :run, "execute[manage brew analaytics]", :immediately
      notifies :upgrade, "homebrew_package[homebrew_core standard packages]", :immediately
    end

    do_filesystem_permissions
  end

  def do_uninstall
    sh = "#{Chef::Config[:file_cache_path]}/homebrew_uninstall.sh"
    remote_file "homebrew's uninstall.sh" do
      path sh
      source node["homebrew"]["uninstall"]["url"]
      checksum node["homebrew"]["uninstall"]["checksum"]
      mode "0700"
      retries 2
      action :create
    end

    execute "homebrew's uninstall.sh" do
      command sh
      returns new_resource.force ? [0, 1] : 0
      timeout 480
    end

    directory "homebrew's root" do
      path Homebrew.root
      recursive true
      only_if { Homebrew.arm64? }
      action :delete
    end
  end

  def prepare
    sudo "chef-homebrew_core-xcode-install" do
      user new_resource.owner
      commands ["/usr/bin/touch", "/usr/sbin/softwareupdate"]
      nopasswd true
      only_if { new_resource.xcode_cli_tools }
      action :nothing
      notifies :delete, "sudo[chef-homebrew_core-xcode-install]", :delayed
    end

    build_essential "homebrew_core install xcode Command Line Tools" do
      action :nothing
      notifies :create, "sudo[chef-homebrew_core-xcode-install]", :before
    end

    homebrew_package "homebrew_core standard packages" do
      package_name new_resource.standard_packages
      not_if { new_resource.standard_packages.empty? }
      action :nothing
    end

    execute "manage brew analaytics" do
      command "#{Homebrew.bin} analytics #{new_resource.analytics ? "on" : "off"}"
      user new_resource.owner
      login true
      ignore_failure true
      action :nothing
      not_if { new_resource.analytics.nil? }
    end
  end

  def repair
    script "unshallow homebrew taps" do
      code <<~HERE
      for tap in #{::File.join(Homebrew.lib, "Library/Taps/homebrew")}/homebrew-*; do
        if cd "$tap"; then
          if [[ $(git -C "$tap" rev-parse --is-shallow-repository) != *"false"* ]]; then
            git -C "$tap" fetch --unshallow
          fi
        fi
      done
      HERE
      interpreter "zsh"
      user new_resource.owner
      ignore_failure true
      action :nothing
    end

    script "chown ~/Library/*/Homebrew" do
      code <<~HERE
      for d in /Users/#{new_resource.owner}/Library/*/Homebrew; do
        chown -R #{new_resource.owner} $d
      done
      HERE
      interpreter "zsh"
      ignore_failure true
      action :nothing
    end
  end

  def why_not_run_log
    Chef::Log.debug(
      "homebrew_core checks:\n macos?#{macos?} emulated_chef?#{Homebrew.emulated_chef?}\n " +
      "can_install?#{can_install?} can_uninstall?#{can_uninstall?}\n " +
      "#{new_resource.owner}:valid_owner?#{!node["homebrew-core"]["disallowed-owners"].include?(new_resource.owner)}\n " +
      "homebrew_core attributes:\n #{node["homebrew-core"]}\n"
    )
    Chef::Log.warn("homebrew_core cannot complete #{new_resource.action[0]}")
    nil
  end
end

action :install, description: "Install brew, dependencies, and standard packages." do
  return why_not_run_log unless can_install?

  prepare
  if new_resource.force || Homebrew.missing?
    converge_by "install homebrew core" do
      do_install
    end
  end
end

action :upgrade, description: "Install/update brew, dependencies, and standard packages. With brew_update_frequency 0, run an immediate update, otherwise schedule periodic updates." do
  return why_not_run_log unless can_install?

  prepare
  if new_resource.force || Homebrew.missing?
    converge_by "installing homebrew core" do
      do_install
    end
  else
    repair
    converge_by "update homebrew core" do
      homebrew_update "periodic brew update" do
        frequency new_resource.brew_update_frequency
        ignore_failure true
        action :periodic
        notifies :run, "script[chown ~/Library/*/Homebrew]", :before
        notifies :run, "script[unshallow homebrew taps]", :before
        notifies :run, "execute[manage brew analaytics]", :immediately
        notifies :upgrade, "homebrew_package[homebrew_core standard packages]", :immediately
        notifies(
          :upgrade,
          "build_essential[homebrew_core install xcode Command Line Tools]",
          :before
        )
      end
    end
  end
end

action :uninstall, description: "Unistall brew and all packages." do
  return why_not_run_log unless can_uninstall?

  if new_resource.force || Homebrew.exists? || ::File.exists?(Homebrew.lib)
    converge_by "uninstall homebrew core" do
      do_uninstall
    end
  end
end
