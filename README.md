## Homebrew Core Cookbook

[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](https://opensource.org/licenses/Apache-2.0)

##### Requirements

- macOS
- Chef 17+

This cookbook installs and updates [Homebrew](http://brew.sh/) and applies several patches to the core chef homebrew resources.

`homebrew_tap`, `homebrew_cask`, and `homebrew_update` were built by [sous-chefs.org](https://sous-chefs.org/). The sous-chef's [homebrew cookbook](https://github.com/sous-chefs/homebrew) also can also install homebrew. If this cookbook could work for you, make sure to consider theirs as well.

Homebrew Core solves the install challenge as simply as possible. It also includes several conveniences specific to my use cases.

- Xcode cli install/update is automatically included prior to brew install or update. Uses `build_essential` core resource. A required but emphemeral `/etc/sudoers` edit is performed.

- `homebrew_core` wraps `homebrew_update`, a standard chef resource.

- The `homebrew_package` understands versions, and can install, uninstall, and upgrade historical brew packages. This feature brought to you courtesy of `brew --extract`.

- The `:uninstall` action can also now be versioned.

- A `:purge` action now exists. Simply adds `--force` to uninstall, though.

- A recipe, `formula.rb`, shims custom formula files into locally tapped casks.

- Monkey patched minor bugfixes, QoL & style changes, etc - often opinionated. Perhaps often wrongheaded. Caveat emptor.

## Resource: homebrew_core

##### Actions

- `:install` - install homebrew
- `:upgrade` - install homebrew if missing, periodically `brew update` via `homebrew_update` resource
- `:uninstall` - remove homebrew, its packages and unique directories

##### Properties

- `owner` - String - homebrew owner's macOS account. Default: `Homebrew.owner`.
- `force` - Bool - force install or uninstall homebrew, regardless of state.
- `analytics` - Bool - if false `brew analytics off` is run during `:install` and `:upgrade` actions
- `xcode_cli_tools` - Bool - install or upgrade Xcode Command Line Tools. Default: `true`.
- `standard_packages` - Array - homebrew packages to install/upgrade alongside homebrew.
- `brew_update_frequency` - Integer - seconds between periodic homebrew updates. Values less than the interval between chef runs will resolve to the latter. Ignored on all but the `:upgrade` action. Default: 86400s (1 day).

### Attributes

```ruby
default["homebrew-core"] = {
  # Custom formula to add to homebrew/cask Tap.
  "custom-formulae" => [
    # Ignored unless a brew formula is found at `homebrew/files/Formula/
    "my-custom-package@1.1.2"
  ],

  # Refuse to manage homebrew if calculated owner account is one of these.
  "disallowed-owners" => [
    "root",
    "_mbsetupuser"
  ],

  # Script URL required for `:install` and `upgrade` actions. Checksum optional.
  "install" => {
    "url" => "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh",
    "checksum" => nil,
    "allowed" => true
  },

  # Script URL required for `:uninstall` action. Checksum optional.
  "uninstall" => {
    "url" => "https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh",
    "checksum" => nil,
    "allowed" => true
  }
}
```

### Recipes

##### `default`

Runs `homebrew_core` with `:upgrade` action.

##### `formula`

Adds custom formulae to the local homebrew-cask tap. Allows adding arbitrary homebrew packages to an install. See `files/Formula/README.md`.

## Usage

Works on macOS only, naturally.

### homebrew_core

For the simplest use, place "recipe[homebrew-core]" anywhere in your nodes' run list. You may also use the `homebrew_core` resource from any other recipe.

Simple package installs are easiest if they are included in `standard_packages`. Otherwise, ensure your `homebrew_packages` executions occur after `homebrew_core` converges.

#### `:install`

Installs cli tools, homebrew, then `standard_packages`. If homebrew is already installed, no action is taken, and core packages will not be installed.

Operator must define `["homebrew-core"]["install"]["url"]`.

#### `:upgrade`

If the periodic `brew_update_frequency` has not expired since last logged update, no action taken.

Otherwise, installs/updates cli tools, homebrew, then `standard_packages`. If homebrew is already installed, installs/updates cli tools, installs/updates packages.

#### About `homebrew_update`

Periodic updates are achieved using the standard chef resource [`homebrew_update`](https://docs.chef.io/resources/homebrew_update/).

The `brew_update_frequency` param is passed directly to updates's `frequency`. The `:periodic` action is always used.

If you wish to execute non-periodically - on every chef run - simply set this frequency lower than your nodes' chef-client execution period.

#### `:uninstall`

Removes brew and brew packages with their official uninstall script. Deletes all paths their uninstall script suggests for optional deletion.

Operator must define `["homebrew-core"]["uninstall"]["url"]`.

### homebrew_package

Install, upgrade, and uninstall now support a `version` parameter. Historical brew packages in the `homebrew/cask` tap may be installed.

Optionally, one may specify the version in the package name instead of the param, using brew's pattern: `package@<version>`.

### Examples

```ruby
homebrew_core "Delete homebrew" do
  action                      :uninstall
  force                       true
end

# Installs older 2.2.42 awscli build.
# Verified this version's formula exists using
# https://github.com/Homebrew/homebrew-core/commits/master/Formula/awscli.rb
homebrew_package "awscli" do
  action :upgrade
  version "2.2.42"
end

homebrew_core "Install/update homebrew, depedencies, and base packages" do
  action                      :upgrade
  force                       false
  xcode_cli_tools             true
  standard_packages           ["dory"]
  brew_update_frequency       600
end
```

##### Example output

```shell
Recipe: homebrew-core::default
  * homebrew_core[Install/update homebrew, depedencies, and base packages] action upgrade
    * sudo[chef-homebrew_core-xcode-install] action nothing (skipped due to action :nothing)
    * build_essential[homebrew_core install xcode Command Line Tools] action nothing (skipped due to action :nothing)
    * build_essential[homebrew_core install xcode Command Line Tools] action nothing (skipped due to action :nothing)
    * homebrew_package[homebrew_core standard packages] action nothing (skipped due to action :nothing)
    * execute[manage brew analaytics] action nothing (skipped due to action :nothing)
    * script[unshallow homebrew taps] action nothing (skipped due to action :nothing)
    * script[chown ~/Library/*/Homebrew] action nothing (skipped due to action :nothing)
    * homebrew_update[periodic brew update] action periodic
      - Would update new lists of packages
    * script[chown ~/Library/*/Homebrew] action run
      - execute "zsh"
    * script[unshallow homebrew taps] action run
      - execute "zsh"
    * build_essential[homebrew_core install xcode Command Line Tools] action upgrade (up to date)
    * build_essential[homebrew_core install xcode Command Line Tools] action upgrade (up to date)
    * homebrew_update[periodic brew update] action periodic
      * directory[/var/lib/homebrew/periodic] action create (up to date)
      * file[/var/lib/homebrew/periodic/update-success-stamp] action create_if_missing (up to date)
      * execute[brew update] action run
        - execute ["brew", "update"]
      * file[/var/lib/homebrew/periodic/update-success-stamp] action touch
        - update utime on file /var/lib/homebrew/periodic/update-success-stamp
      - update new lists of packages
    * execute[manage brew analaytics] action run
      - execute /opt/homebrew/bin/brew analytics off
    * homebrew_package[homebrew_core standard packages] action upgrade
      - upgrade(allow_downgrade) package dory from uninstalled to 1.1.1
    - update homebrew core
```

## License and Authors

This cookbook is maintained by Harry Seeber. Large parts were originally forked from open sourcce code maintained by sos-chefs and chef. The original author, maintainer and copyright holder of much derived work is Graeme Mathieson.

All code is licensed under the Apache License version 2.

[Original blog post by Graeme](https://woss.name/articles/converging-your-home-directory-with-chef/)

Author:: Graeme Mathieson ([mathie@woss.name](mailto:mathie@woss.name))
Author:: Joshua Timberman ([joshua@chef.io](mailto:joshua@chef.io))
Author:: Harry Seeber ([git@sysop.ooo](mailto:git@sysop.ooo))

```text
Copyright:: 2011, Graeme Mathieson
Copyright:: 2012-2016, Chef Software, Inc. <legal@chef.io>
Copyright:: 2022, Harry Seeber

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
