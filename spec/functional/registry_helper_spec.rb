#
# Author:: Prajakta Purohit (<prajakta@opscode.com>)
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

require 'chef/win32/registry'

describe 'Chef::Win32::Registry', :windows_only do

  before(:all) do
    #Create a registry item
    ::Win32::Registry::HKEY_CURRENT_USER.create "Software\\Root"
    ::Win32::Registry::HKEY_CURRENT_USER.create "Software\\Root\\Branch"
    ::Win32::Registry::HKEY_CURRENT_USER.create "Software\\Root\\Branch\\Flower"
    ::Win32::Registry::HKEY_CURRENT_USER.open('Software\\Root', Win32::Registry::KEY_ALL_ACCESS) do |reg|
      reg['RootType1', Win32::Registry::REG_SZ] = 'fibrous'
      reg.write('Roots', Win32::Registry::REG_MULTI_SZ, ["strong roots", "healthy tree"])
    end
    ::Win32::Registry::HKEY_CURRENT_USER.open('Software\\Root\\Branch', Win32::Registry::KEY_ALL_ACCESS) do |reg|
      reg['Strong', Win32::Registry::REG_SZ] = 'bird nest'
    end
    ::Win32::Registry::HKEY_CURRENT_USER.open('Software\\Root\\Branch\\Flower', Win32::Registry::KEY_ALL_ACCESS) do |reg|
      reg['Petals', Win32::Registry::REG_MULTI_SZ] = ["Pink", "Delicate"]
    end

    #Create the node with ohai data
    events = Chef::EventDispatch::Dispatcher.new
    @node = Chef::Node.new
    ohai = Ohai::System.new
    ohai.all_plugins
    @node.consume_external_attrs(ohai.data,{})
    @run_context = Chef::RunContext.new(@node, {}, events)

    #Create a registry object that has access ot the node previously created
    @registry = Chef::Win32::Registry.new(@run_context, 'x86_64')
  end

  #Delete what is left of the registry key-values previously created
  after(:all) do
    ::Win32::Registry::HKEY_CURRENT_USER.open("Software") do |reg|
      reg.delete_key("Root", true)
    end
  end

  # Operating system
  # it "succeeds if the operating system is windows" do
  # end

  # Server Versions
  # it "succeeds if server versiion is 2003R2, 2008, 2008R2, 2012" do
  # end
  # it "falis if the server versions are anything else" do
  # end

  # If hive_exists
  it "returns true if the hive exists" do
    hive = @registry.hive_exists?("HKCU\\Software\\Root")
    hive.should == true
  end
  it "returns false if the hive does not exist" do
    hive = @registry.hive_exists?("LYRU\\Software\\Root")
    hive.should == false
  end

  #  key_exists
  it "returns true if the key path exists" do
    exists = @registry.key_exists?("HKCU\\Software\\Root\\Branch\\Flower")
    exists.should == true
  end
  it "returns false if the key path does not exist" do
    exists = @registry.key_exists?("HKCU\\Software\\Branch\\Flower")
    exists.should == false
  end
  it "returns an error if the hive does not exist" do
    lambda {@registry.key_exists?("JKLM\\Software\\Branch\\Flower")}.should raise_error(Chef::Exceptions::Win32RegHiveMissing)
  end

  # get_values
  it "returns all values for a key if it exists" do
    values = @registry.get_values("HKCU\\Software\\Root")
    values.should be_an_instance_of Array
    values.should == [{:name=>"RootType1", :type=>1, :data=>"fibrous"},
                      {:name=>"Roots", :type=>7, :data=>["strong roots", "healthy tree"]}]
  end
  it "returns an error if the key does not exist" do
    lambda {@registry.get_values("HKCU\\Software\\Branch\\Flower")}.should raise_error(Chef::Exceptions::Win32RegKeyMissing)
  end

  #  update_value
  it "updates a value if the key, value exist and type matches and value different" do
    @registry.update_value("HKCU\\Software\\Root\\Branch\\Flower", {:name=>"Petals", :type=>:multi_string, :data=>["Yellow", "Changed Color"]})
    ::Win32::Registry::HKEY_CURRENT_USER.open("Software\\Root\\Branch\\Flower", Win32::Registry::KEY_ALL_ACCESS) do |reg|
      reg.each do |name, type, data|
        if name == 'Petals'
          if data == ["Yellow", "Changed Color"]
            @exists=true
          else
            @exists=false
          end
        end
      end
    end
    @exists.should == true
    #Chef::Log.should_receive(:debug).with("Value is updated")
    end
    it "gives an error if key and value exists and type does not match" do
      lambda {@registry.update_value("HKCU\\Software\\Root\\Branch\\Flower", {:name=>"Petals", :type=>:string, :data=>"Yellow"})}.should raise_error(Chef::Exceptions::Win32RegTypesMismatch)
    end
    it "gives an error if key exists and value does not" do
      lambda {@registry.update_value("HKCU\\Software\\Root\\Branch\\Flower", {:name=>"Stamen", :type=>:multi_string, :data=>["Yellow", "Changed Color"]})}.should raise_error(Chef::Exceptions::Win32RegValueMissing)
    end
    it "does nothing if data,type and name parameters for  the value are same" do
      @registry.update_value("HKCU\\Software\\Root\\Branch\\Flower", {:name=>"Petals", :type=>:multi_string, :data=>["Yellow", "Changed Color"]})
      ::Win32::Registry::HKEY_CURRENT_USER.open("Software\\Root\\Branch\\Flower", Win32::Registry::KEY_ALL_ACCESS) do |reg|
        reg.each do |name, type, data|
          if name == 'Petals'
            if data == ["Yellow", "Changed Color"]
              @exists=true
            else
              @exists=false
            end
          end
        end
        #Chef::Log.should_receive("Data is the same, value not updated")
      end
    end
    it "gives an error if the key does not exist" do
      lambda {@registry.update_value("HKCU\\Software\\Branch\\Flower", {:name=>"Petals", :type=>:multi_string, :data=>["Yellow", "Changed Color"]})}.should raise_error(Chef::Exceptions::Win32RegKeyMissing)
    end

    #  create_value
    it "creates a value if it does not exist" do
      creates = @registry.create_value("HKCU\\Software\\Root\\Branch\\Flower", {:name=>"Buds", :type=>:string, :data=>"Closed"})
      ::Win32::Registry::HKEY_CURRENT_USER.open("Software\\Root\\Branch\\Flower", Win32::Registry::KEY_ALL_ACCESS) do |reg|
        reg.each do |name, type, data|
          if name == "Buds" && type == 1 && data == "Closed"
            @exists=true
          else
            @exists=false
          end
        end
      end
    end
    it "throws an exception if the value exists" do
      lambda {@registry.create_value("HKCU\\Software\\Root\\Branch\\Flower", {:name=>"Buds", :type=>:string, :data=>"Closed"})}.should raise_error(Chef::Exceptions::Win32RegValueExists)
      ::Win32::Registry::HKEY_CURRENT_USER.open("Software\\Root\\Branch\\Flower", Win32::Registry::KEY_ALL_ACCESS) do |reg|
        reg.each do |name, type, data|
          if name == "Buds" && type == 1 && data == "Closed"
            @exists=true
          else
            @exists=false
          end
        end
      end
      @exists.should == true
      #test with timestamp?
    end

    #  create_key
    it "gives an error if the path has missing keys but recursive set to false" do
      created = @registry.create_key("HKCU\\Software\\Root\\Trunk\\Peck\\Woodpecker", {:name=>"Peter", :type=>:string, :data=>"Little"}, false)
      ::Win32::Registry::HKEY_CURRENT_USER.open("Software\\Root", Win32::Registry::KEY_ALL_ACCESS) do |reg|
        reg.each_key do |key_name|
          if key_name == "Trunk"
            @exists=true
            break
          else
            @exists=false
          end
        end
      end
      @exists.should == false
    end
    it "creates the key_path if the keys were missing but recursive was set to true" do
      @registry.create_key("HKCU\\Software\\Root\\Trunk\\Peck\\Woodpecker", {:name=>"Peter", :type=>:string, :data=>"Little"}, true)
      ::Win32::Registry::HKEY_CURRENT_USER.open("Software\\Root\\Trunk\\Peck\\Woodpecker", Win32::Registry::KEY_ALL_ACCESS) do |reg|
        reg.each do|name, type, data|
          if name == "Peter" && type == 1 && data == "Little"
            @exists=true
          else
            @exists=false
          end
        end
      end
      @exists.should == true
    end
    it "does nothing if the key already exists" do
      @registry.create_key("HKCU\\Software\\Root\\Trunk\\Peck\\Woodpecker", {:name=>"Peter", :type=>:string, :data=>"Little"}, false)
      ::Win32::Registry::HKEY_CURRENT_USER.open("Software\\Root\\Trunk\\Peck\\Woodpecker", Win32::Registry::KEY_ALL_ACCESS) do |reg|
        reg.each do|name, type, data|
          if name == "Peter" && type == 1 && data == "Little"
            @exists=true
          else
            @exists=false
          end
        end
      end
      @exists.should == true
    end

    #  create_if_missing
    it "does not update a key if it exists" do
      @registry.create_key("HKCU\\Software\\Root\\Trunk\\Peck\\Woodpecker", {:name=>"Peter", :type=>:string, :data=>"Tiny"}, true)
      ::Win32::Registry::HKEY_CURRENT_USER.open("Software\\Root\\Trunk\\Peck\\Woodpecker", Win32::Registry::KEY_ALL_ACCESS) do |reg|
        reg.each do |name, type, data|
          if name == "Peter" && type == 1 && data == "Little"
            @exists=true
          elsif name == "Peter" && type == 1 && data == "Tiny"
            @exists=false
          end
        end
      end
      @exists.should == true
    end

    it "makes no changes to value even if it exists and type matches" do
      @registry.create_key("HKCU\\Software\\Root\\Trunk\\Peck\\Woodpecker", {:name=>"Peter", :type=>:string, :data=>"Little will remain unchanged"}, true)
      ::Win32::Registry::HKEY_CURRENT_USER.open("Software\\Root\\Trunk\\Peck\\Woodpecker", Win32::Registry::KEY_ALL_ACCESS) do |reg|
        reg.each do |name, type, data|
          if name == "Peter" && type == 1 && data == "Little"
            @exists=true
          elsif name == "Peter" && type == 1 && data == "Little will remain unchanged"
            @exists=false
          end
        end
      end
      @exists.should == true
    end

    #  delete_values
    it "deletes values if the value exists" do
      @registry.delete_value("HKCU\\Software\\Root\\Trunk\\Peck\\Woodpecker", {:name=>"Peter", :type=>:string, :data=>"Tiny"})
      exists = false
      ::Win32::Registry::HKEY_CURRENT_USER.open("Software\\Root\\Trunk\\Peck\\Woodpecker", Win32::Registry::KEY_ALL_ACCESS) do |reg|
        reg.each do |name, type, data|
          if name == "Peter" && type == 1 && data == "Little"
            exists=true
            break
          else
            exists=false
          end
        end
      end
      exists.should == false
    end
    it "does nothing if value does not exist" do
       @registry.delete_value("HKCU\\Software\\Root\\Trunk\\Peck\\Woodpecker", {:name=>"Peter", :type=>:string, :data=>"Tiny"})
       #what to test for fall through ?
    end

    #  delete_key
    it "gives an error if the hive does not exist" do
     lambda {@registry.delete_key("JKLM\\Software\\Root\\Branch\\Flower", {:name=>"Buds", :type=>:string, :data=>"Closed"}, false)}.should raise_error(Chef::Exceptions::Win32RegHiveMissing)
    end
    context "If the action is to delete" do
      before (:all) do
        #40 - 23757182 ajit dada
        ::Win32::Registry::HKEY_CURRENT_USER.create "Software\\Root\\Branch\\Fruit"
        ::Win32::Registry::HKEY_CURRENT_USER.open('Software\\Root\\Branch\\Fruit', Win32::Registry::KEY_ALL_ACCESS) do |reg|
          reg['Apple', Win32::Registry::REG_MULTI_SZ] = ["Red", "Juicy"]
        end
      end
    it "deletes a key if it has no subkeys" do
      @registry.delete_key("HKCU\\Software\\Root\\Branch\\Fruit", {:name=>"Apple", :type=>:multi_string, :data=>["Red", "Juicy"]}, false)
      exists = false
      ::Win32::Registry::HKEY_CURRENT_USER.open("Software\\Root\\Branch", Win32::Registry::KEY_ALL_ACCESS) do |reg|
        reg.each_key do |name|
          if name == "Fruit"
            exists=true
            break
          else
            exists=false
          end
        end
      end
      exists.should == false
    end
    it "gives an error if key to delete has subkeys and recursive is false" do
      @registry.delete_key("HKCU\\Software\\Root\\Trunk", {:name=>"Strong", :type=>:string, :data=>"bird nest"}, false)
      exists = true
      ::Win32::Registry::HKEY_CURRENT_USER.open("Software\\Root", Win32::Registry::KEY_ALL_ACCESS) do |reg|
        reg.each_key do |name|
          if name == "Trunk"
            exists=true
            break
          else
            exists=false
          end
        end
      end
      exists.should == true
    end
    it "deletes a key if it has subkeys and recursive true" do
      @registry.delete_key("HKCU\\Software\\Root\\Trunk", {:name=>"Strong", :type=>:string, :data=>"bird nest"}, true)
      exists = true
      ::Win32::Registry::HKEY_CURRENT_USER.open("Software\\Root", Win32::Registry::KEY_ALL_ACCESS) do |reg|
        reg.each_key do |name|
          if name == "Trunk"
            exists=true
            break
          else
            exists=false
          end
        end
      end
      exists.should == false
    end
      it "does nothing if the key does not exist" do
        @registry.delete_key("HKCU\\Software\\Root\\Trunk", {:name=>"Strong", :type=>:string, :data=>"bird nest"}, true)
        exists = true
        ::Win32::Registry::HKEY_CURRENT_USER.open("Software\\Root", Win32::Registry::KEY_ALL_ACCESS) do |reg|
          reg.each_key do |name|
            if name == "Trunk"
              exists=true
              break
            else
              exists=false
            end
          end
        end
        exists.should == false
      end
    end

    # has_subkeys
     it "would give an exception if the hive was missing" do
        lambda {@registry.has_subkeys?("LMNO\\Software\\Root")}.should raise_error(Chef::Exceptions::Win32RegHiveMissing)
     end
    # it "would give and exception if the key was missing" do
    # end
    it "returns true if the key has subkeys" do
      subkeys = @registry.has_subkeys?("HKCU\\Software\\Root")
      exists = false
      ::Win32::Registry::HKEY_CURRENT_USER.open("Software\\Root", Win32::Registry::KEY_ALL_ACCESS) do |reg|
        reg.each_key{|name| exists=true}
      end
      subkeys.should == true
    end

    #  get_subkeys
    #  tests for keys or hive missing
    it "returns the array of subkeys for a given key" do
      subkeys = @registry.get_subkeys("HKCU\\Software\\Root")
      reg_subkeys = []
      ::Win32::Registry::HKEY_CURRENT_USER.open("Software\\Root", Win32::Registry::KEY_ALL_ACCESS) do |reg|
        reg.each_key{|name| reg_subkeys << name}
      end
      reg_subkeys.should == subkeys
    end

    it "returns the requested_architecture if architecture specified is 32bit but CCR on 64 bit" do
      @registry.registry_system_architecture == 0x0100
    end

   # it "returns the requested_architecture if architecture specified is 32bit but CCR on 64 bit" do
   #   reg = Chef::Win32::Registry.new(@run_context, "i386")
   #   reg.registry_constant = 0x0100
   # end

    context "If the architecture is correct" do
      before(:all) do
        #       #how to preserve the original ohai and reapply later ?
        node = Chef::Node.new
        node.automatic_attrs[:kernel][:machine] = "i386"
        events = Chef::EventDispatch::Dispatcher.new
        @rc = Chef::RunContext.new(node, {}, events)
      end
      it "returns false if architecture is specified as 64bit but CCR on 32bit" do
        lambda {Chef::Win32::Registry.new(@rc, "x86_64")}.should raise_error(Chef::Exceptions::Win32RegArchitectureIncorrect)
      end
      it "returns the architecture_requested if architecture specified and architecture of the CCR box matches" do
        reg = Chef::Win32::Registry.new(@rc, "i386")
        reg.registry_system_architecture == 0x0200
      end
 #     
 #     #key_exists
 #     #it "returns an error if the architecture is wrong" do
 #     #    lambda {@registry.key_exists?("HKCU\\Software\\Branch\\Flower")}.should raise_error(Chef::Exceptions::Win32RegArchitectureIncorrect)
 #     #end
 #     #create_key
 #     #create_value
 #     #update_value
 #     #get_value
 #     #delete_Value
 #     #delete_key
 #     #has_subkey
 #     #get_subkey
 #     #it "returns false if the system architecture says 32bit but system is 64bit" do
 #      #pending
 #     #end

    end

  end
