#
# Author:: Harry Seeber (<git@sysop.ooo>)
# Cookbook:: homebrew-core
# Libraries:: helpers
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


class HomebrewUserWrapper
  require 'chef/mixin/homebrew_user'
  include Chef::Mixin::HomebrewUser
end

module Homebrew
  extend self # rubocop:disable ModuleFunction
  include Chef::Mixin::ShellOut

  def bin
    @bin ||= ::File.join(prefix, "brew")
  end

  def exists?
    !emulated_chef? && ::File.exist?(bin)
  end

  def group
    @group ||= owner.nil? ? "admin" : Etc.getpwnam(owner).uid
  end

  def missing?
    !exists?
  end

  def owner
    @owner ||= begin
      # even with chef >14, keep using this wrapper: chef's implementation
      # assumes intel-only brew paths or that `which brew` always works.
      # neither are assured.
      Etc.getpwuid(HomebrewUserWrapper.new.find_homebrew_uid).name
    rescue Chef::Exceptions::CannotDetermineHomebrewOwner
      calculate_owner
    end.tap do |owner|
      Chef::Log.debug("Homebrew owner is #{owner}")
    end
  end

  def package_info(package_name)
    return {} unless exists? && !owner.nil?

    begin
      JSON.parse(
        shell_out!("#{bin} info \"#{package_name}\" --json", user: owner).stdout
      )[0]
    rescue Mixlib::ShellOut::ShellCommandFailed, JSON::ParserError
      {}
    end
  end

  def prefix
    @bin_dir ||= ::File.join(root, "bin")
  end

  def arm64?
    @arm64 ||= shell_out!('/usr/sbin/sysctl -a machdep.cpu.brand_string').stdout.include?('Apple M1')
  end

  def emulated_chef?
    arm64? && !/arm64-.*/.match?(RUBY_PLATFORM)
  end

  def lib
    @lib ||= arm64? ? root : "#{root}/Homebrew"
  end

  def root
    @root ||= arm64? ? "/opt/homebrew" : "/usr/local"
  end

  alias_method :exist?, :exists?
end unless defined?(Homebrew)

class Chef
  class Provider
    class Package
      class Homebrew < Chef::Provider::Package
        def brew_cmd_output(*command, **options)
          brew_exec(*command, **options).stdout.chomp
        end

        def brew_exec(*command, **options)
          homebrew_user = Etc.getpwnam(::Homebrew.owner)
          homebrew_uid = homebrew_user.uid
          shell_out_cmd = options[:allow_failure] ? :shell_out : :shell_out!
          logger.trace "Executing '#{::Homebrew.bin} #{command.join(" ")}' as user '#{homebrew_user.name}'"

          public_send(
            *[shell_out_cmd, ::Homebrew.bin, command].flatten,
            user: homebrew_uid,
            timeout: 1800,
            environment: {
              "HOME" => homebrew_user.dir, "RUBYOPT" => nil, "TMPDIR" => nil
            }
          )
        end

        def extract_formula(name, version)
          brew_exec("extract", "--force", "--version=#{version}", name, "homebrew/cask", allow_failure: true)
        end

        def formulae_for(names, versions)
          i = 0
          names.map do |name|
            next if name.nil?

            target_version = versions[i]
            i += 1

            if target_version.nil? || target_version == available_version(name)
              name
            elsif package_info("#{name}@#{target_version}").any?
              "#{name}@#{target_version}"
            elsif !extract_formula(name, target_version).error?
              "#{name}@#{target_version}"
            end
          end.compact
        end

        def install_package(names, versions)
          formulae = formulae_for(names, versions)
          return if formulae.empty?

          Chef::Log.info("Installing brew packages: #{formulae}")
          brew_exec("install", options, formulae)
        end

        def installed_version(i)
          p_data = package_info(i)

          if p_data["linked_keg"].is_a?(String)
            p_data["linked_keg"].split("_")[0]
          elsif p_data["keg_only"]
            if p_data["installed"].empty?
              nil
            else
              p_data["installed"].last["version"]
            end
          else
            p_data["linked_keg"]
          end
        end

        def upgrade_package(names, versions)
          # @todo when we no longer support Ruby 2.6 this can be simplified to be a .filter_map
          upgrade_pkgs = names.reject { |x| installed_version(x).nil? }
          install_pkgs = names.select { |x| installed_version(x).nil? }
          upinned_pkgs = upgrade_pkgs.reject { |x| [nil, available_version(x)].include?(versions[names.index(x)]) }
          upgrade_pkgs = upgrade_pkgs - upinned_pkgs
          install_pkgs = install_pkgs + upinned_pkgs
          install_pkgs_versions = install_pkgs.map { |x| versions[names.index(x)] }

          brew_exec("upgrade", options, upgrade_pkgs) unless upgrade_pkgs.empty?
          install_package(install_pkgs, install_pkgs_versions) unless install_pkgs.empty?
        end

        def remove_package(names, versions)
          formulae = formulae_for(names, versions)
          return unless formulae.any?

          Chef::Log.info("Removing brew packages: #{formulae}")
          brew_exec("uninstall", options, formulae)
        end

        def purge_package(names, versions)
          formulae = formulae_for(names, versions)
          return unless formulae.any?

          Chef::Log.info("Purging brew packages: #{formulae}")
          brew_exec("uninstall", "--force", options, formulae)
        end
      end
    end
  end
end
