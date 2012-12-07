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

      def initialize(run_context=nil)
        @run_context = run_context
      end

      def node
        run_context && run_context.node
      end

      def get_values(key_path, architecture)
        key = get_key(key_path)
        hive = get_hive(key_path)
        unless key_exists?(key_path, architecture)
          raise Chef::Exceptions::Win32RegKeyMissing, "message"
        end
        values = []
        hive.open(key) do |reg|
          reg.each do |name, type, data| 
            value={:name=>name, :type=>type, :data=>data}
            values << value
          end
        end
        return values
      end

      def update_value(key_path, value, architecture)
        if value_exists?(key_path, value, architecture)
          if type_matches?(key_path, value, architecture)
            hive = get_hive(key_path)
            key = get_key(key_path)
            hive.open(key, ::Win32::Registry::KEY_ALL_ACCESS) do |reg|
              reg.each{|name, type, data|
                if value[:name] == name
                  if data != value[:data]
                    reg.write(value[:name], get_type_from_name(value[:type]), value[:data])
                    return true
                  else
                    puts "Data is the same not updated"
                    return "no_action"
                  end
                else
                  puts "Value does not exist --- check if we want to include create_if_missing here"
                  return false
                end
              }
            end
          else
            puts "Types do not match"
            return false
          end
        else
          puts "Value does not exist -- it could be key does not exist"
          return false
        end
      end

      def create_value(key_path, value, architecture)
        hive = get_hive(key_path)
        unless !value_exists?(key_path, value, architecture)
          raise Chef::Exceptions::Win32RegValueExists, "message"
        end
        key = get_key(key_path)
        hive.open(key, ::Win32::Registry::KEY_ALL_ACCESS) do |reg|
          reg.write(value[:name], get_type_from_name(value[:type]), value[:data])
        end
      end

      def create_key(key_path, value, architecture, recursive)
        hive = get_hive(key_path)
        if architecture_correct?(architecture)
          if keys_missing?(key_path, architecture)
            if recursive == true
              create_missing(key_path, architecture)
              key = get_key(key_path)
              hive.create key
              create_value(key_path, value, architecture)
              return true
            end
          else
            unless key_exists?(key_path, architecture)
              hive.create key_path
              create_value(key_path, value, architecture)
              return true
            end
             return true
          end
        end
        #Chef.log.debug("Key #{key_path} not created")
        return false
      end

      def delete_value(key_path, value, architecture)
        hive = get_hive(key_path)
        if key_exists?(key_path, architecture)
          key = get_key(key_path)
          hive.open(key, ::Win32::Registry::KEY_ALL_ACCESS) do |reg|
            reg.delete_value(value[:name])
          end
        end
      end

      def delete_key(key_path, value, architecture, recursive)
        hive = get_hive(key_path)
        key = get_key(key_path)
        key_parent = key.split("\\")
        key_to_delete = key_parent.pop
        key_parent = key_parent.join("\\")
        if has_subkeys(key_path, architecture)
          if recursive == true
            hive.open(key_parent, ::Win32::Registry::KEY_WRITE) do |reg|
              reg.delete_key(key_to_delete,true)
            end
          end
        else
          hive.open(key_parent, ::Win32::Registry::KEY_WRITE) do |reg|
            reg.delete_key(key_to_delete)
          end
        end
      end

      def has_subkeys(key_path, architecture)
        hive = get_hive(key_path)
        subkeys = nil
        unless key_exists?(key_path, architecture)
          raise Chef::Exceptions::Win32RegKeyMissing, "message"
        end
        key = get_key(key_path)
        hive.open(key) do |reg|
          reg.each_key{ |key| return true }
        end
        return false
      end

      def get_subkeys(key_path, architecture)
        subkeys = []
        hive = get_hive(key_path)
        unless key_exists?(key_path, architecture)
          raise Chef::Exceptions::Win32RegKeyMissing, "message"
        end
        key = get_key(key_path)
        hive.open(key) do |reg|
          reg.each_key{ |current_key| subkeys << current_key }
        end
        return subkeys
      end

      def key_exists?(key_path, architecture)
        unless architecture_correct?(architecture)
          raise Chef::Exceptions::Win32RegArchitectureIncorrect, "message"
        end
        hive = get_hive(key_path)
        key = get_key(key_path)
        begin
          hive.open(key, ::Win32::Registry::Constants::KEY_READ) do |current_key|
            return true
          end
        rescue
          return false
        end
      end

      def hive_exists?(key_path)
        hive = get_hive(key_path)
        Chef::Log.debug("Registry hive resolved to #{hive}")
        unless hive
          return false
        end
        return true
      end

      private

      def get_hive(path)
        Chef::Log.debug("Resolving registry shortcuts from path to full names")

        reg_path = path.split("\\")
        hive_name = reg_path.shift

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
        #unless hive
        #  Chef::Application.fatal!("Unsupported registry hive '#{hive_name}'")
        #end
        return hive
      end

      def get_key(path)
        reg_path = path.split("\\")
        hive_name = reg_path.shift
        key = reg_path.join("\\")
        return key
      end

      def architecture_correct?(user_architecture)
        # Returns false if requesting for a 64but architecture on a 32 bit system
        system_architecture = node[:kernel][:machine]
        return true if system_architecture == "x86_64"
        return (user_architecture == "i386")
      end

      def value_exists?(key_path, value, architecture)
        if key_exists?(key_path, architecture)
          hive = get_hive(key_path)
          key = get_key(key_path)
          hive.open(key) do |reg|
            reg.each do |val_name|
              if val_name == value[:name]
                return true
              end
            end
          end
        end
        return false
      end

      def type_matches?(key_path, value, architecture)
        if value_exists?(key_path, value, architecture)
          hive = get_hive(key_path)
          key = get_key(key_path)
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

      def keys_missing?(key_path, architecture)
        missing_key_arr = key_path.split("\\")
        missing_key_arr.pop
        key = missing_key_arr.join("\\")
        !key_exists?(key, architecture)
      end

      def create_missing(key_path, architecture)
        missing_key_arr = key_path.split("\\")
        hivename = missing_key_arr.shift
        missing_key_arr.pop
        existing_key_path = hivename
        hive = get_hive(key_path)
        missing_key_arr.each do |intermediate_key|
          existing_key_path = existing_key_path << "\\" << intermediate_key
          if !key_exists?(existing_key_path, architecture)
            hive.create get_key(existing_key_path)
          end
        end
      end

    end
  end
end
