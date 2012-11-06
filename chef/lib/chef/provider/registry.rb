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

#??include Windows::RegistryHelper

require 'chef/config'
require 'chef/log'
require 'chef/resource/file'
require 'chef/mixin/checksum'
require 'chef/provider'
require 'etc'
require 'fileutils'
require 'chef/scan_access_control'
require 'chef/mixin/shell_out'
require 'chef/win32/registry'

class Chef

  class Provider
    class Registry < Chef::Provider
      include Chef::Mixin::Checksum
      include Chef::Mixin::ShellOut

      def load_current_resource
        # Every child should be specifying their own constructor, so this
        # should only be run in the file case.
        @current_resource ||= Chef::Resource::Registry.new(@new_resource.key_name)
        @current_resource.values(@new_resource.values)
        path = @new_resource.key_name.split("\\")
        path.shift
        key = path.join("\\")
        if Chef::Win32::Registry.key_exists?(key, true)
          if Chef::Win32::Registry.value_exists?(@new_resource.key_name, @new_resource.values)
            hive = Chef::Win32::Registry.get_hive(@new_resource.get_hive)
            hive.open(key, ::Win32::Registry::KEY_ALL_ACCESS) do |reg|
              @new_resource.values.each do |k, val|
                @current_resource.type, @current_resource.values = reg.read(k)
              end
            end
          end
        end
        @current_resource
      end

      def action_create
        if Chef::Win32::Registry.key_exists?(key, true)
          if Chef::Win32::Registry.value_exists?(@new_resource.key_name, @new_resource.values)
            registry_update(:modify)
          end
        end
        registry_update(:create)
      end

     # def action_modify
     #   registry_update(:open)
     # end

     # def action_force_modify
     #   require 'timeout'
     #   Timeout.timeout(120) do
     #     @new_resource.values.each do |value_name, value_data|
     #       i = 1
     #       until i > 5 do
     #         desired_value_data = value_data
     #         current_value_data = get_value(@new_resource.key_name.dup, value_name.dup)
     #         if current_value_data.to_s == desired_value_data.to_s
     #           Chef::Log.debug("#{@new_resource} value [#{value_name}] desired [#{desired_value_data}] data already set. Check #{i}/5.")
     #           i+=1
     #         else
     #           Chef::Log.debug("#{@new_resource} value [#{value_name}] current [#{current_value_data}] data not equal to desired [#{desired_value_data}] data. Setting value and restarting check loop.")
     #           begin
     #             registry_update(:open)
     #           rescue Exception
     #             registry_update(:create)
     #           end
     #           i=0 # start count loop over
     #         end
     #       end
     #     end
     #     break
     #   end
     # end

      def action_remove
        Chef::Win32::Registry::delete_value(@new_resource.key_name,@new_resource.values)
      end

      private
      def registry_update(mode)

        Chef::Log.debug("Registry Mode (#{mode})")
        updated = Chef::Win32::Registry::set_value(mode,@new_resource.key_name,@new_resource.values,@new_resource.type)
        @new_resource.updated_by_last_action(updated)
      end
    end
  end
end
