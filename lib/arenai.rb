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

      if %w(mysql mysql2).include? connection.pool.spec.config[:adapter]
        # SELECT "users".* FROM "users" WHERE "users"."id" = ?  [["id", 1]]
        find_by_sql("SELECT #{quoted_table_name}.* FROM #{quoted_table_name} WHERE #{quoted_table_name}.#{connection.quote_column_name primary_key} = #{id}").first
      else
        # SELECT "users".* FROM "users" WHERE "users"."id" = ?  [["id", 1]]
        find_by_sql("SELECT #{quoted_table_name}.* FROM #{quoted_table_name} WHERE #{quoted_table_name}.#{connection.quote_column_name primary_key} = ?", [[columns_hash[primary_key], id]]).first
      end
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
        when String, Array
          condition = @klass.send(:sanitize_sql, rest.empty? ? opts : ([opts] + rest))
          @arenai_values[:where] << "(#{condition})"
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
      return super if from_value || joins_values.any? || includes_values.any? || eager_load_values.any? || preload_values.any? || references_values.any? || lock_value
      return super if where_values.size != @arenai_values[:where].size
      return super if order_values.size != @arenai_values[:order].size

      sql = 'sELECT'
      sql << ' DISTINCT' if distinct_value
      sql << (select_values.any? ? " #{select_values.join(', ')}" : " #{quoted_table_name}.*")
      sql << " FROM #{quoted_table_name}"
      sql << " WHERE #{@arenai_values[:where].join(' AND ')}" if @arenai_values[:where].any?
      sql << " GROUP BY #{group_values.join(', ')}" if group_values.any?
      sql << " HAVING #{having_values.join(' AND ')}" if having_values.any?
      sql << " ORDER BY #{@arenai_values[:order].join(', ')}" if @arenai_values[:order].any?
      sql << " LIMIT #{limit_value}" if limit_value
      sql << " OFFSET #{offset_value}" if offset_value
      @records = @klass.find_by_sql sql, []

      @records.each { |record| record.readonly! } if readonly_value

      @loaded = true
      @records
    end

    private def rebuild_relation
      @arenai_values.inject(self) do |rel, (key, value)|
        ActiveRecord::Relation.instance_method(key).super_method().bind(rel).call(value)
      end
    end
  end
end

ActiveSupport.on_load :active_record do
  class << ActiveRecord::Base
    prepend Arenai::Base
  end

  ActiveRecord::Relation.prepend Arenai::Relation
end
