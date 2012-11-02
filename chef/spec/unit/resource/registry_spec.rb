#
# Author:: Prajakta Purohit (<prajakta@opscode.com>)
# Copyright:: Copyright (c) 2008 Opscode, Inc.
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

  before(:each) do
    @resource = Chef::Resource::Registry.new("reg_key")
  end

  it "should have a name" do
    @resource.key_name.should eql("reg_key")
  end

  it "should have a default action of 'modify'" do
    @resource.action.should eql(:modify)
  end

#  it "should have a default content of nil" do
#    @resource.content.should be_nil
#  end

  it "should only accept strings for key_name" do
    lambda { @resource.key_name 5 }.should raise_error(ArgumentError)
    lambda { @resource.key_name :foo }.should raise_error(ArgumentError)
    lambda { @resource.key_name "hello" => "there" }.should raise_error(ArgumentError)
    lambda { @resource.key_name "hi" }.should_not raise_error(ArgumentError)
  end

  it "should only accept hash for values" do
    @resource.values "I_am_the_reg_key" => "hah_and_I_am_your_value"
    @resource.values.should == {"I_am_the_reg_key" => "hah_and_I_am_your_value"}
  end

  it "should only accept symbol for type" do
    @resource.type :binary
    @resource.type.should ba_a_kind_of(Hash)
  end

#  it "should accept a string as the path" do
#    lambda { @resource.path "/tmp" }.should_not raise_error(ArgumentError)
#    @resource.path.should eql("/tmp")
#    lambda { @resource.path Hash.new }.should raise_error(ArgumentError)
#  end

#  describe "when it has a path, owner, group, mode, and checksum" do
#    before do
#      @resource.path("/tmp/foo.txt")
#      @resource.owner("root")
#      @resource.group("wheel")
#      @resource.mode("0644")
#      @resource.checksum("1" * 64)
#    end

#    context "on unix", :unix_only do
#      it "describes its state" do
#        state = @resource.state
#        state[:owner].should == "root"
#        state[:group].should == "wheel"
#        state[:mode].should == "0644"
#        state[:checksum].should == "1" * 64
#      end
#    end

#    context "on windows", :windows_only do
      # according to Chef::Resource::File, windows state attributes are rights + deny_rights
#      pending "it describes its state"
#    end

    it "returns the key_name as its identity" do
      @resource.identity.should == "reg_key"
    end

#  end

#  describe "when access controls are set on windows", :windows_only => true do
#    before do
#      @resource.rights :read, "Everyone"
#      @resource.rights :full_control, "DOMAIN\User"
#    end
#    it "describes its state including windows ACL attributes" do
#      state = @resource.state
#      state[:rights].should == [ {:permissions => :read, :principals => "Everyone"},
#                               {:permissions => :full_control, :principals => "DOMAIN\User"} ]
#    end
#  end

end

