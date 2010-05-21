# This is the core permission class that Permissive uses.
module Permissive
  class Permission < ActiveRecord::Base
    belongs_to :permitted_object, :polymorphic => true
    belongs_to :scoped_object, :polymorphic => true
    named_scope :granted, lambda {|*permissions|
      {:conditions => permissions.flatten.map{|bit| "(mask & #{bit}) > 0"}.join(' AND ')}
    }
    named_scope :on, lambda {|scoped_object|
      case scoped_object
      when ActiveRecord::Base
        {:conditions => {:scoped_object_id => scoped_object.id, :scoped_object_type => scoped_object.class.to_s}}
      when Class
        {:conditions => {:scoped_object_id => nil, :scoped_object_type => scoped_object.name}}
      when String, Symbol
        {:conditions => {:scoped_object_id => nil, :scoped_object_type => scoped_object.to_s.classify}}
      else
        {:conditions => {:scoped_object_id => nil, :scoped_object_type => nil}}
      end
    }
    set_table_name :permissive_permissions
    validates_presence_of :mask, :permitted_object
  end
end