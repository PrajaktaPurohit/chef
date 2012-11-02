#
# Author:: Prajakta Purohit (<schisamo@opscode.com>)
# Copyright:: Copyright (c) 2011 Opscode, Inc.
# License:: Apache License, Version 2.0
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

require 'spec_helper'

describe Chef::Resource::Registry do
  include_context Chef::Resource::Registry

  let(:file_base) { "file_spec" }
  #let(:expected_content) { "Don't fear the ruby." }

  def create_resource
    events = Chef::EventDispatch::Dispatcher.new
    node = Chef::Node.new
    run_context = Chef::RunContext.new(node, {}, events)
    resource = Chef::Resource::Registry.new("HKCU\Software\Test", run_context)
    resource
  end

  let!(:resource) do
    create_resource
  end

  it_behaves_like "a registry resource"

  context "when the registry value does not exist" do
    it "it creates the registry entry when the action is create" do
     # resource.key_name("HKCU\Software\Test")
      resource.values({'Apple' => ['Red', 'Sweet', 'Juicy']})
      resource.type(:multi_string)
      resource.run_action(:create)
      Win32::Registry.get_value(resource.path, resource.value) == {'Apple' => ['Red', 'Sweet', 'Juicy']}
    end
 #   it "modifys a key with value" do
 #     resource.run_action(:modify)
 #   end
  end

 # context "when the registry value exists and the action is :remove" do
 #   it "Removes the registry entry" do
 #     resource.run_action(:remove)
 #   end
 # end

end
