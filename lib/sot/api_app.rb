require 'sinatra/base'
require 'sinatra/json'
require 'json'

module SOT
  class ApiApp < Sinatra::Base
    helpers Sinatra::JSON

    before do
      content_type :json
    end

    helpers do
      def current_user
        env['sot.current_user']
      end

      def require_admin!
        unless current_user&.admin?
          halt 403, json(error: 'Admin access required.')
        end
      end

      def parse_json_body
        body = request.body.read
        return {} if body.empty?

        JSON.parse(body)
      rescue JSON::ParserError
        halt 400, json(error: 'Invalid JSON in request body.')
      end
    end

    # --- Schema endpoints ---

    get '/schemas' do
      all_schemas = SOT::SchemaService.list(namespace: params[:namespace])
      schemas = all_schemas.select { |s| SOT::PermissionService.can?(current_user, s, :read) }
      json(schemas: schemas.map { |s| serialize_schema(s) })
    end

    # --- Record endpoints ---

    get '/records/:table' do
      schema = SOT::SchemaService.resolve(params[:table])
      halt 404, json(error: "Table '#{params[:table]}' not found.") unless schema
      halt 404, json(error: "Table '#{params[:table]}' not found.") unless SOT::PermissionService.can?(current_user, schema, :read)

      filters = params[:filters] ? JSON.parse(params[:filters]) : {}
      halt 400, json(error: 'Filters must be a JSON object.') unless filters.is_a?(Hash)

      unknown = filters.keys.map(&:to_s) - schema.all_field_names
      unless unknown.empty?
        halt 400, json(error: "Unknown filter fields: #{unknown.join(', ')}. Valid fields: #{schema.all_field_names.join(', ')}")
      end

      search = params[:search] ? JSON.parse(params[:search]) : []
      search = Array(search)

      records = SOT::QueryService.list(
        [schema.id],
        filters: filters,
        search: search,
        state: params[:state],
        limit: (params[:limit] || 50).to_i,
        offset: (params[:offset] || 0).to_i
      )
      count = SOT::QueryService.count([schema.id], filters: filters, search: search, state: params[:state])

      json(records: records.map { |r| serialize_record(r) }, total: count)
    rescue JSON::ParserError
      halt 400, json(error: 'Invalid JSON in filters parameter.')
    end

    post '/records' do
      data = parse_json_body
      table = data['table']
      halt 400, json(error: "'table' is required.") unless table

      schema = SOT::SchemaService.resolve(table)
      halt 404, json(error: "Table '#{table}' not found.") unless schema

      record = SOT::MutationService.create(
        schema: schema,
        data: data['data'] || {},
        state: data['state'],
        user: current_user
      )

      [201, json(record: serialize_record(record))]
    rescue SOT::PermissionService::PermissionDenied
      halt 404, json(error: "Table '#{data['table']}' not found.")
    rescue SOT::MutationService::ValidationError => e
      halt 422, json(error: e.message)
    end

    patch '/records/:id' do
      record = SOT::Record[params[:id].to_i]
      halt 404, json(error: "Record ##{params[:id]} not found.") unless record

      data = parse_json_body
      updated = SOT::MutationService.update(
        record: record,
        data: data['data'],
        state: data['state'],
        preconditions: data['preconditions'],
        user: current_user,
        replace_data: data['replace_data'] || false,
        append_data: data['append_data'],
        expected_version: data['version']
      )

      json(record: serialize_record(updated))
    rescue SOT::PermissionService::PermissionDenied
      halt 404, json(error: "Record ##{params[:id]} not found.")
    rescue SOT::MutationService::VersionConflict => e
      halt 409, json(error: e.message)
    rescue SOT::MutationService::PreconditionFailed => e
      halt 409, json(error: e.message)
    rescue SOT::MutationService::ValidationError => e
      halt 422, json(error: e.message)
    end

    delete '/records/:id' do
      record = SOT::Record[params[:id].to_i]
      halt 404, json(error: "Record ##{params[:id]} not found.") unless record

      data = parse_json_body
      SOT::MutationService.delete(
        record: record,
        preconditions: data['preconditions'],
        user: current_user,
        expected_version: data['version']
      )

      json(message: "Deleted record ##{params[:id]}.")
    rescue SOT::PermissionService::PermissionDenied
      halt 404, json(error: "Record ##{params[:id]} not found.")
    rescue SOT::MutationService::VersionConflict => e
      halt 409, json(error: e.message)
    rescue SOT::MutationService::PreconditionFailed => e
      halt 409, json(error: e.message)
    rescue SOT::MutationService::ValidationError => e
      halt 422, json(error: e.message)
    end

    # --- Users ---

    get '/users' do
      users = SOT::UserService.list.select(&:is_active)
      json(users: users.map { |u| { id: u.id, name: u.name } })
    end

    # --- Activity log ---

    get '/activity_log' do
      dataset = SOT::ActivityLog.order(Sequel.desc(:created_at))

      readable_ids = SOT::PermissionService.readable_schema_ids(current_user)
      dataset = dataset.where(schema_id: readable_ids)

      if params[:table]
        schema = SOT::SchemaService.resolve(params[:table])
        halt 404, json(error: "Table '#{params[:table]}' not found.") unless schema && SOT::PermissionService.can?(current_user, schema, :read)
        dataset = dataset.where(schema_id: schema.id)
      end

      dataset = dataset.where(record_id: params[:record_id].to_i) if params[:record_id]
      dataset = dataset.where(action: params[:action]) if params[:action]

      count = dataset.count
      entries = dataset.limit((params[:limit] || 50).to_i).offset((params[:offset] || 0).to_i).all

      json(entries: entries.map { |e| serialize_activity_log(e) }, total: count)
    end

    # --- Admin endpoints ---

    post '/admin/schemas' do
      require_admin!
      data = parse_json_body

      acl = {}
      %w[read_roles create_roles update_roles delete_roles].each do |key|
        acl[key.to_sym] = data[key] if data.key?(key)
      end

      schema = SOT::SchemaService.create(
        namespace: data['namespace'],
        name: data['name'],
        description: data['description'],
        fields: data['fields'] || [],
        states: data['states'],
        **acl
      )

      [201, json(schema: serialize_schema(schema))]
    rescue ArgumentError => e
      halt 422, json(error: e.message)
    end

    patch '/admin/schemas/:id' do
      require_admin!
      schema = SOT::Schema[params[:id].to_i]
      halt 404, json(error: "Schema ##{params[:id]} not found.") unless schema

      data = parse_json_body
      update_attrs = {}
      update_attrs[:description] = data['description'] if data.key?('description')
      update_attrs[:fields] = data['fields'] if data.key?('fields')
      update_attrs[:states] = data['states'] if data.key?('states')
      %w[read_roles create_roles update_roles delete_roles].each do |key|
        update_attrs[key.to_sym] = data[key] if data.key?(key)
      end

      updated = SOT::SchemaService.update(schema, **update_attrs)

      json(schema: serialize_schema(updated))
    rescue ArgumentError => e
      halt 422, json(error: e.message)
    end

    delete '/admin/schemas/:id' do
      require_admin!
      schema = SOT::Schema[params[:id].to_i]
      halt 404, json(error: "Schema ##{params[:id]} not found.") unless schema

      schema.destroy
      json(message: "Deleted schema '#{schema.full_name}'.")
    rescue Sequel::ForeignKeyConstraintViolation
      halt 409, json(error: "Cannot delete table '#{schema.full_name}': it has associated activity log entries. Delete those first.")
    end

    private

    def serialize_schema(s)
      {
        id: s.id,
        namespace: s.namespace,
        name: s.name,
        full_name: s.full_name,
        description: s.description,
        fields: s.parsed_fields,
        states: s.parsed_states,
        stateful: s.stateful?,
        created_at: s.created_at&.iso8601,
        updated_at: s.updated_at&.iso8601
      }
    end

    def serialize_record(r)
      {
        id: r.id,
        version: r.current_version,
        schema_id: r.schema_id,
        data: r.parsed_data,
        state: r.state,
        created_by: r.created_by,
        updated_by: r.updated_by,
        created_at: r.created_at&.iso8601,
        updated_at: r.updated_at&.iso8601
      }
    end

    def serialize_activity_log(e)
      {
        id: e.id,
        user_id: e.user_id,
        record_id: e.record_id,
        schema_id: e.schema_id,
        action: e.action,
        changes: e.parsed_changes,
        created_at: e.created_at&.iso8601
      }
    end
  end
end
