#
# Author:: Harry Seeber (<git@sysop.ooo>)
# Cookbook:: homebrew-core
# Attributes:: default
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

default["homebrew-core"] = {
  "custom-formulae" => [
    "devspace@5.17.0-beta.6",
  ],

  "disallowed-owners" => [
    "root",
    "_mbsetupuser",
  ],

  "install" => {
    "url" => "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh",
    "checksum" => nil,
    "allowed" => true
  },

  "uninstall" => {
    "url" => "https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh",
    "checksum" => nil,
    "allowed" => true
  }
}
