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
        # SELECT "users".* FROM "users" WHERE "users"."id" = $1  [["id", 1]]
        find_by_sql("SELECT #{quoted_table_name}.* FROM #{quoted_table_name} WHERE #{quoted_table_name}.#{connection.quote_column_name primary_key} = $1", [[columns_hash[primary_key], id]]).first
      end
    end
  end

  module Relation
    def initialize(*)
      super
      @arenai_values ||= Hash.new.tap {|h| h[:where], h[:order], h[:original_where_params], h[:original_order_params] = [], [], [], []}
    end

    def to_sql
      return super if where_values.any? || from_value || joins_values.any? || includes_values.any? || eager_load_values.any? || preload_values.any? || references_values.any? || lock_value

      sql = 'SELECT'
      sql << ' DISTINCT' if distinct_value
      sql << (select_values.any? ? " #{select_values.join(', ')}" : " #{quoted_table_name}.*")
      sql << " FROM #{quoted_table_name}"
      sql << " WHERE #{@arenai_values[:where].join(' AND ')}" if @arenai_values[:where].any?
      sql << " GROUP BY #{group_values.join(', ')}" if group_values.any?
      sql << " HAVING #{having_values.join(' AND ')}" if having_values.any?
      sql << " ORDER BY #{@arenai_values[:order].join(', ')}" if @arenai_values[:order].any?
      sql << " LIMIT #{limit_value}" if limit_value
      sql << " OFFSET #{offset_value}" if offset_value
      sql
    end

    def calculate(*args)
      rebuild_relation.method(:calculate).super_method.call(*args)
    end

    def exists?(*args)
      rebuild_relation.method(:exists?).super_method.call(*args)
    end

    def rebuild_relation
#       ret = @arenai_values.except(:where, :order).inject(self) do |rel, (key, value)|
#         rel.send key, value
#       end
      ret = self
      @arenai_values[:original_where_params].each do |opts, rest|
        ret = ret.method(:where).super_method.call opts, *rest
      end
      @arenai_values[:original_order_params].each do |args|
        ret = ret.method(:order).super_method.call(*args)
      end
      ret
    end

#    private def build_relation_from_arenai_values
#      ret = self
#      @arenai_values[:where].each do |w|
#        ret = ret.arenai_original(:where, w)
#      end
#      #TODO handle multiple values
#      ret = ret.order(@arenai_values[:order]) if @arenai_values[:order].any?
#      ret
#    end

    #TODO `or` method
    def where(opts = :chain, *rest)
      if (opts == :chain) || opts.blank?
        rebuild_relation.method(:where).super_method.call(opts, *rest)
      else
        @arenai_values[:original_where_params] << [opts, rest]

        case opts
        when String, Array
          condition = @klass.send(:sanitize_sql, rest.empty? ? opts : ([opts] + rest))
          @arenai_values[:where] << "(#{condition})"
          self
        when Hash
          return rebuild_relation if (opts.keys.map(&:to_s) - klass.attribute_names).any?

          opts.each_pair do |k, v|
            case v
            when Array
              #FIXME handle nil
              if v.include? nil
                return rebuild_relation
              end
              compact_v = v.compact
              if compact_v.one?
                @arenai_values[:where] << "#{quoted_table_name}.#{connection.quote_column_name k} = #{connection.quote compact_v.first}"
              elsif compact_v.empty?
              else
                @arenai_values[:where] << "#{quoted_table_name}.#{connection.quote_column_name k} IN (#{compact_v.map {|vv| connection.quote vv}.join(', ')})"
              end
            when ActiveRecord::Base
              @arenai_values[:where] << "#{quoted_table_name}.#{connection.quote_column_name k} = #{v.id}"
            #TODO
            when Hash
              return rebuild_relation
            when nil
              @arenai_values[:where] << "#{quoted_table_name}.#{connection.quote_column_name k} IS NULL"
            else
              @arenai_values[:where] << "#{quoted_table_name}.#{connection.quote_column_name k} = #{connection.quote v}"
            end
          end
          self
        else
          rebuild_relation
        end
      end
    end

    def order(*args)
      @arenai_values[:original_order_params] << [args]

      if args.all? {|a| (String === a) || (Symbol === a) }
        args.each do |o|
          case o
          when String
            @arenai_values[:order] << o
          when Symbol
            @arenai_values[:order] << "#{quoted_table_name}.#{connection.quote_column_name o}"
          end
        end
        self
      else
        rebuild_relation
      end
    end

    if ActiveRecord::VERSION::MAJOR >= 5
      def where_values() where_clause; end
      def from_value() from_clause; end
    end

    private def exec_queries
      return super if where_values.any? || from_value || joins_values.any? || includes_values.any? || eager_load_values.any? || preload_values.any? || references_values.any? || lock_value
      @records = @klass.find_by_sql to_sql, []

      @records.each { |record| record.readonly! } if readonly_value

      @loaded = true
      @records
    end
  end

  module DatabaseStatements
    def binds_from_relation(relation, binds)
      if relation.is_a?(Relation) && binds.empty?
        super relation.rebuild_relation, binds
      else
        super
      end
    end
  end
end

ActiveSupport.on_load :active_record do
  class << ActiveRecord::Base
    prepend Arenai::Base
  end

  ActiveRecord::Relation.prepend Arenai::Relation

  ActiveRecord::ConnectionAdapters::AbstractAdapter.prepend Arenai::DatabaseStatements
end
