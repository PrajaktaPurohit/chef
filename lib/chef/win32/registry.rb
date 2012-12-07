#
# Author:: Doug MacEachern (<dougm@vmware.com>)
# Author:: Seth Chisamore (<schisamo@opscode.com>)
# Author:: Paul Morton (<pmorton@biaprotect.com>)
# Cookbook Name:: windows
# Provider:: registry
#
# Copyright:: 2010, VMware, Inc.
# Copyright:: 2011, Opscode, Inc.
# Copyright:: 2011, Business Intelligence Associates, Inc
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
require 'chef/reserved_names'

if RUBY_PLATFORM =~ /mswin|mingw32|windows/
  require 'win32/registry'
  require 'ruby-wmi'
end
class Chef
  class Win32
    class Registry

      attr_accessor :run_context
      attr_accessor :architecture, :machine

      def initialize(run_context=nil, user_architecture=:machine)
        @run_context = run_context
        self.architecture = user_architecture
      end

      def node
        run_context && run_context.node
      end

      def assert_architecture!
        if node[:kernel][:machine] == "i386" && architecture == "x86_64"
          raise Chef::Exceptions::Win32RegArchitectureIncorrect, "cannot access 64-bit registry on a 32-bit windows instance"
        end
      end

      def architecture=(user_architecture)
        @architecture = user_architecture
        assert_architecture!
      end

      def registry_system_architecture
        applied_arch = ( architecture == :machine ) ? node[:kernel][:machine] : architecture
        ( applied_arch == 'x86_64' ) ? 0x0100 : 0x0200
      end

      def get_values(key_path)
        hive, key = get_hive_and_key(key_path)
        key_exists!(key_path)
        values = []
        hive.open(key) do |reg|
          reg.each do |name, type, data|
            value={:name=>name, :type=>type, :data=>data}
            values << value
          end
        end
        return values
      end

      def update_value(key_path, value)
       value_exists!(key_path, value)
        unless type_matches?(key_path, value)
          raise Chef::Exceptions::Win32RegTypesMismatch, "message"
        end
        hive, key = get_hive_and_key(key_path)
        hive.open(key, ::Win32::Registry::KEY_SET_VALUE | ::Win32::Registry::KEY_QUERY_VALUE | registry_system_architecture) do |reg|
          reg.each do |name, type, data|
            if value[:name] == name
              if data != value[:data]
                reg.write(value[:name], get_type_from_name(value[:type]), value[:data])
                Chef::Log.debug("Value is updated")
              else
                Chef::Log.debug("Data is the same, value not updated")
              end
            end
          end
        end
      end

      def create_value(key_path, value)
        unless !value_exists?(key_path, value)
          raise Chef::Exceptions::Win32RegValueExists, "message"
        end
        hive, key = get_hive_and_key(key_path)
        hive.open(key, ::Win32::Registry::KEY_SET_VALUE | registry_system_architecture) do |reg|
          reg.write(value[:name], get_type_from_name(value[:type]), value[:data])
          Chef::Log.debug("Created value")
        end
      end

      def create_key(key_path, value, recursive)
        if keys_missing?(key_path)
          if recursive == true
            puts "in recurssive = true"
            create_missing(key_path)
          else
            puts "in recurssive = false"
            Chef::Log.debug("Key #{key_path} not created")
            return
          end
        end
        hive, key = get_hive_and_key(key_path)
        hive.create key
        Chef::Log.debug("Key #{key_path} created")
        unless value_exists?(key_path, value)
          create_value(key_path, value)
        end
      end

      def delete_value(key_path, value)
        begin
          if value_exists?(key_path, value)
            hive, key = get_hive_and_key(key_path)
            hive.open(key, ::Win32::Registry::KEY_SET_VALUE | registry_system_architecture) do |reg|
              reg.delete_value(value[:name])
              Chef::Log.debug("Deletes value #{value[:name]}")
            end
          end
        rescue Chef::Exceptions::Win32RegKeyMissing => e
        end
      end

      #do we want delete key to return true or false if it does actions ?
      def delete_key(key_path, value, recursive)
        hive, key = get_hive_and_key(key_path)
        key_parent = key.split("\\")
        key_to_delete = key_parent.pop
        key_parent = key_parent.join("\\")
        unless !key_exists?(key_path)
          if has_subkeys?(key_path)
            if recursive == true
              hive.open(key_parent, ::Win32::Registry::KEY_WRITE | registry_system_architecture) do |reg|
                reg.delete_key(key_to_delete,true)
              end
            end
          else
            hive.open(key_parent, ::Win32::Registry::KEY_WRITE | registry_system_architecture) do |reg|
              reg.delete_key(key_to_delete)
            end
          end
        end
      end

      def has_subkeys?(key_path)
        subkeys = nil
        key_exists!(key_path)
          hive, key = get_hive_and_key(key_path)
          hive.open(key) do |reg|
            reg.each_key{ |key| return true }
          end
          return false
      end

      def get_subkeys(key_path)
        subkeys = []
        key_exists!(key_path)
        hive, key = get_hive_and_key(key_path)
        hive.open(key) do |reg|
          reg.each_key{ |current_key| subkeys << current_key }
        end
        return subkeys
      end

      def key_exists?(key_path)
        hive, key = get_hive_and_key(key_path)
        begin
          hive.open(key, ::Win32::Registry::KEY_READ | registry_system_architecture) do |current_key|
            return true
          end
        rescue ::Win32::Registry::Error => e
          return false
        end
      end

      def key_exists!(key_path)
        unless key_exists?(key_path)
          raise Chef::Exceptions::Win32RegKeyMissing, "message"
        end
      end

      def hive_exists?(key_path)
        begin
        hive, key = get_hive_and_key(key_path)
        Chef::Log.debug("Registry hive resolved to #{hive}")
        rescue Chef::Exceptions::Win32RegHiveMissing => e
          return false
        end
        return true
      end

      private

      def get_hive_and_key(path)
        Chef::Log.debug("Resolving registry shortcuts from path to full names")

        reg_path = path.split("\\")
        hive_name = reg_path.shift
        key = reg_path.join("\\")

        hive = {
          "HKLM" => ::Win32::Registry::HKEY_LOCAL_MACHINE,
          "HKU" => ::Win32::Registry::HKEY_USERS,
          "HKCU" => ::Win32::Registry::HKEY_CURRENT_USER,
          "HKCR" => ::Win32::Registry::HKEY_CLASSES_ROOT,
          "HKCC" => ::Win32::Registry::HKEY_CURRENT_CONFIG
        }[hive_name]

        unless hive
          raise Chef::Exceptions::Win32RegHiveMissing, "message"
        end
        return hive, key
      end

      def value_exists?(key_path, value)
        key_exists!(key_path)
        hive, key = get_hive_and_key(key_path)
        hive.open(key) do |reg|
          return true if reg.any? {|val| val == value[:name] }
        end
        return false
      end

      def value_exists!(key_path, value)
        unless value_exists?(key_path, value)
          raise Chef::Exceptions::Win32RegValueMissing, "message"
        end
      end

      def type_matches?(key_path, value)
        value_exists!(key_path, value)
        hive, key = get_hive_and_key(key_path)
        hive.open(key) do |reg|
          reg.each do |val_name, val_type|
            if val_name == value[:name]
              type_new = get_type_from_name(value[:type])
              if val_type == type_new
                return true
              end
            end
          end
        end
        return false
      end

      def get_type_from_name(val_type)
        value = {
          :binary => ::Win32::Registry::REG_BINARY,
          :string => ::Win32::Registry::REG_SZ,
          :multi_string => ::Win32::Registry::REG_MULTI_SZ,
          :expand_string => ::Win32::Registry::REG_EXPAND_SZ,
          :dword => ::Win32::Registry::REG_DWORD,
          :dword_big_endian => ::Win32::Registry::REG_DWORD_BIG_ENDIAN,
          :qword => ::Win32::Registry::REG_QWORD
        }[val_type]
        return value
      end

      def keys_missing?(key_path)
        missing_key_arr = key_path.split("\\")
        missing_key_arr.pop
        key = missing_key_arr.join("\\")
        !key_exists?(key)
      end

      def create_missing(key_path)
        missing_key_arr = key_path.split("\\")
        hivename = missing_key_arr.shift
        missing_key_arr.pop
        existing_key_path = hivename
        hive, key = get_hive_and_key(key_path)
        missing_key_arr.each do |intermediate_key|
          existing_key_path = existing_key_path << "\\" << intermediate_key
          if !key_exists?(existing_key_path)
            hive.create get_key(existing_key_path)
          end
        end
      end

      def get_key(path)
        reg_path = path.split("\\")
        hive_name = reg_path.shift
        key = reg_path.join("\\")
      end

    end
  end
end
