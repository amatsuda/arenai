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

    def where(opts = :chain, *rest)
      if (opts == :chain) || opts.blank?
        super
      else
        case opts
        when String
          @arenai_values[:where] << "(#{opts})"
        when Hash
          opts.each_pair do |k, v|
            case v
            #TODO
            when Array, Hash, ActiveRecord::Base
              # do nothing
            when nil
              @arenai_values[:where] << "#{quoted_table_name}.#{connection.quote_column_name k} IS NULL"
            else
              @arenai_values[:where] << "#{quoted_table_name}.#{connection.quote_column_name k} = #{connection.quote v}"
            end
          end
        end
        super
      end
    end

    def order(*args)
      args.each do |o|
        case o
        when String
          @arenai_values[:order] << o
        when Symbol
          @arenai_values[:order] << "#{quoted_table_name}.#{connection.quote_column_name o}"
        end
      end
      super
    end

    private def exec_queries
      return super if joins_values.any? || includes_values.any?
      return super if where_values.size != @arenai_values[:where].size
      return super if order_values.size != @arenai_values[:order].size

      sql = "SELECT #{quoted_table_name}.* FROM #{quoted_table_name}"
      sql = "#{sql} WHERE #{@arenai_values[:where].join(' AND ')}" if @arenai_values[:where].any?
      sql = "#{sql} ORDER BY #{@arenai_values[:order].join(', ')}" if @arenai_values[:order].any?
      @records = @klass.find_by_sql sql, []

      @records.each { |record| record.readonly! } if readonly_value

      @loaded = true
      @records
    end
  end
end

ActiveSupport.on_load :active_record do
  class << ActiveRecord::Base
    prepend Arenai::Base
  end

  ActiveRecord::Relation.prepend Arenai::Relation
end
