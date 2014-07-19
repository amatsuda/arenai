require "arenai/version"

module Arenai
  module Base
    def find(*ids)
      return super unless ids.length == 1
      return super if block_given? ||
                      primary_key.nil? ||
                      default_scopes.any? ||
                      columns_hash.include?(inheritance_column) ||
                      ids.first.kind_of?(Array)
      id = ids.first
      return super if !((Fixnum === id) || (String === id))

      # SELECT "users".* FROM "users" WHERE "users"."id" = ?  [["id", 1]]
      find_by_sql("SELECT #{quoted_table_name}.* FROM #{quoted_table_name} WHERE #{quoted_table_name}.#{connection.quote_column_name primary_key} = ?", [[User.columns_hash[primary_key], id]]).first
    end
  end

  module Relation
    def initialize(*)
      super
      @arenai_values ||= Hash.new.tap {|h| h[:where], h[:order] = [], []}
    end
  end
end

ActiveSupport.on_load :active_record do
  class << ActiveRecord::Base
    prepend Arenai::Base
  end

  ActiveRecord::Relation.prepend Arenai::Relation
end
