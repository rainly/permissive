module Permissive
  module HasPermissions
    module ClassMethods
      def self.extended(base)

      end

      def has_permissions(options = {}, &block)
        options.assert_valid_keys(:on)

        # Define a permissions method. This will track scoped or global
        # permission levels, depending on how you define them.
        class_eval do
          def self.permissions
            @permissions ||= {}
          end
        end unless respond_to?(:permissions)

        include InstanceMethods

        has_many :permissions, :class_name => 'Permissive::Permission', :as => :permitted_object do
          def can!(*args)
            options = args.extract_options!
            options.assert_valid_keys(:on, :reset)
            options.delete(:on) if options[:on] == :global
            permission_matcher = case options[:on]
            when ActiveRecord::Base
              permission = proxy_owner.permissions.find_or_initialize_by_scoped_object_id_and_scoped_object_type(options[:on].id, options[:on].class.name)
            when Class
              permission = proxy_owner.permissions.find_or_initialize_by_scoped_object_id_and_scoped_object_type(nil, options[:on].name)
            when String, Symbol
              class_name = Permissive::PermissionDefinition.interpolate_scope(proxy_owner.class, options[:on])
              permission = proxy_owner.permissions.find_or_initialize_by_scoped_object_id_and_scoped_object_type(nil, class_name)
            else
              permission = Permissive::Permission.find_or_initialize_by_permitted_object_id_and_permitted_object_type_and_scoped_object_id_and_scoped_object_type(proxy_owner.id, proxy_owner.class.to_s, nil, nil)
            end
            if options[:reset]
              permission.mask = 0
            end
            bits_for(options[:on], args).each do |bit|
              unless permission.mask & bit != 0
                permission.mask = permission.mask | bit
              end
            end
            if proxy_owner.new_record?
              permission.permitted_object = proxy_owner
              proxy_owner.permissions.push(permission)
            else
              permission.save!
            end
            permission
          end

          def can?(*args)
            options = args.extract_options!
            options.assert_valid_keys(:in, :on)
            options[:on] ||= options.delete(:in)
            !on(options[:on]).granted(bits_for(options[:on], args)).empty?
          end

          def revoke(*args)
            options = args.extract_options!
            if args.first == :all
              if options[:on]
                on(options[:on]).destroy_all
              else
                reload.destroy_all
              end
            else
              bits = bits_for(options[:on], args)
              on(options[:on]).each do |permission|
                bits.each do |bit|
                  if permission.mask & bit
                    permission.mask = permission.mask ^ bit
                  end
                end
                permission.save!
              end
            end
          end

          def bits_for(scope, permissions)
            on = Permissive::PermissionDefinition.normalize_scope(proxy_owner.class, scope)
            permissions.flatten.map do |permission|
              permission = permission.to_s.underscore.gsub('/', '_').to_sym
              proxy_owner.class.permissions[on].try(:permissions).try(:[], permission) || proxy_owner.class.permissions[:global].try(:permissions).try(:[], permission)# || raise(Permissive::InvalidPermissionError.new("#{proxy_owner.class.name} does not have a#{'n' if permission.to_s[0, 1].downcase =~ /[aeiou]/} #{permission} permission#{" on #{on}" if on}"))
            end.compact
          end
          private :bits_for
        end

        delegate :can!, :can?, :revoke, :to => :permissions

        permission_definition = Permissive::PermissionDefinition.define(self, options, &block)
        permission_definition.define_methods
        # Oh that's right, it'll return an object.
        permission_definition
      end
      alias :has_permission :has_permissions
    end
  end

  module InstanceMethods
    def method_missing(method, *args)
      if method.to_s =~ /^can(not){0,1}_([^\?]+)(\?|!)$/
        revoke = $1 == "not"
        permissions = $2
        setter = $3 == "!"
        options = args.extract_options!
        options[:on] ||= args.pop
        if permissions =~ /_(on|in)$/
          permissions.chomp!("_#{$1}")
        end
        if options[:on]
          scope = Permissive::PermissionDefinition.normalize_scope(self.class, options[:on])
        else
          scope = :global
        end
        permissions = permissions.split('_and_')
        if permissions.all? {|permission| self.class.permissions[scope].permissions.has_key?(permission.downcase.to_sym) ||
          self.class.permissions[:global].permissions.has_key?(permission.downcase.to_sym) }
          if revoke
            class_eval <<-end_eval
            def #{method}(scope = nil)
              revoke(#{[permissions, args].flatten.join(', ').inspect}, :on => scope)
            end
            end_eval
            return revoke(*[permissions, options].flatten)
          elsif setter
            class_eval <<-end_eval
            def #{method}(scope = nil)
              can!(#{[permissions, args].flatten.join(', ').inspect}, :on => scope)
            end
            end_eval
            return can!(*[permissions, options].flatten)
          else
            class_eval <<-end_eval
            def #{method}(scope = nil)
              can?(#{[permissions, args].flatten.join(', ').inspect}, :on => scope)
            end
            end_eval
            return can?(*[permissions, options].flatten)
          end
        end
      end
      super
    end
  end
end

if defined?(ActiveRecord::Base)
  ActiveRecord::Base.extend Permissive::HasPermissions::ClassMethods
end
