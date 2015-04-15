#
# Copyright 2013-2015, Noah Kantrowitz
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/mash'


module Poise
  module Helpers
    # A resource mixin to add a new kind of attribute, an option collector.
    # These attributes can act as mini-DSLs for things which would otherwise be
    # key/value pairs.
    #
    # @since 1.0.0
    # @example Defining an option collector
    #   class MyResource < Chef::Resource
    #     include Poise::Helpers::OptionCollector
    #     attribute(:my_options, option_collector: true)
    #   end
    # @example Using an option collector
    #   my_resource 'name' do
    #     my_options do
    #       key1 'value1'
    #       key2 'value2'
    #     end
    #   end
    module OptionCollector
      # Instance context used to eval option blocks.
      # @api private
      class OptionEvalContext
        attr_reader :_options

        def initialize(parent)
          @parent = parent
          @_options = {}
        end

        def method_missing(method_sym, *args, &block)
          @parent.send(method_sym, *args, &block)
        rescue NameError
          # Even though method= in the block will set a variable instead of
          # calling method_missing, still try to cope in case of self.method=.
          method_sym = method_sym.to_s.chomp('=').to_sym
          if args.length > 0 || block
            @_options[method_sym] = args.first || block
          elsif !@_options.include?(method_sym)
            # We haven't seen this name before, re-raise the NameError.
            raise
          end
          @_options[method_sym]
        end
      end

      # @!classmethods
      module ClassMethods
        # Override the normal #attribute() method to support defining option
        # collectors too.
        def attribute(name, options={})
          # If present but false-y, make sure it is removed anyway so it
          # doesn't confuse ParamsValidate.
          if options.delete(:option_collector)
            option_collector_attribute(name, options)
          else
            super
          end
        end

        # Define an option collector attribute. Normally used via {.attribute}.
        #
        # @param name [String, Symbol] Name of the attribute to define.
        # @param default [Object] Default value for the options.
        def option_collector_attribute(name, default: {})
          # Unlike LWRPBase.attribute, I don't care about Ruby 1.8. Worlds tiniest violin.
          define_method(name.to_sym) do |arg=nil, &block|
            iv_sym = :"@#{name}"

            value = instance_variable_get(iv_sym) || begin
              default = instance_eval(&default) if default.is_a?(Chef::DelayedEvaluator) # Handle lazy{}
              Mash.new(default) # Wrap in a mash because fuck str vs sym.
            end
            if arg
              raise Exceptions::ValidationFailed, "Option #{name} must be a Hash" if arg && !arg.is_a?(Hash)
              # Should this and the update below be a deep merge?
              value.update(arg)
            end
            if block
              ctx = OptionEvalContext.new(self)
              ctx.instance_exec(&block)
              value.update(ctx._options)
            end
            instance_variable_set(iv_sym, value)
            value
          end
        end

        def included(klass)
          super
          klass.extend(ClassMethods)
        end
      end

      extend ClassMethods
    end
  end
end