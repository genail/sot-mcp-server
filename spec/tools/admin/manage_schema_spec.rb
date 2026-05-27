require 'spec_helper'

RSpec.describe SOT::Tools::Admin::ManageSchema, type: :tool do
  let(:admin) { create(:user, :admin) }

  let(:fields) do
    [{ 'name' => 'title', 'type' => 'string', 'description' => 'Title', 'required' => true }]
  end

  let(:states) do
    [{ 'name' => 'open', 'description' => 'Open' }, { 'name' => 'closed', 'description' => 'Closed' }]
  end

  describe 'create action' do
    it 'creates a schema' do
      response = call_tool(described_class, user: admin,
                           action: 'create', namespace: 'org', name: 'locks',
                           description: 'Resource locks', fields: fields, states: states)
      expect(response_error?(response)).to be_falsey
      expect(response_text(response)).to include("Created table 'org.locks'")
      expect(SOT::Schema.count).to eq(1)
    end

    it 'returns error for invalid fields' do
      response = call_tool(described_class, user: admin,
                           action: 'create', namespace: 'org', name: 'bad',
                           fields: [])
      expect(response_error?(response)).to be true
    end
  end

  describe 'update action' do
    before do
      call_tool(described_class, user: admin,
                action: 'create', namespace: 'org', name: 'locks',
                fields: fields)
    end

    it 'updates description' do
      response = call_tool(described_class, user: admin,
                           action: 'update', table: 'org.locks',
                           description: 'Updated description')
      expect(response_error?(response)).to be_falsey
      expect(SOT::Schema.first.description).to eq('Updated description')
    end

    it 'returns error for unknown table' do
      response = call_tool(described_class, user: admin,
                           action: 'update', table: 'nonexistent')
      expect(response_error?(response)).to be true
    end
  end

  describe 'create action with ACL params' do
    it 'creates a schema with ACL roles' do
      response = call_tool(described_class, user: admin,
                           action: 'create', namespace: 'org', name: 'shared',
                           fields: fields,
                           read_roles: %w[member], create_roles: %w[member],
                           update_roles: [], delete_roles: [])
      expect(response_error?(response)).to be_falsey
      schema = SOT::Schema.first(namespace: 'org', name: 'shared')
      expect(schema.parsed_read_roles).to eq(%w[member])
      expect(schema.parsed_create_roles).to eq(%w[member])
      expect(schema.parsed_update_roles).to eq([])
      expect(schema.parsed_delete_roles).to eq([])
    end

    it 'rejects unknown role names in ACL' do
      response = call_tool(described_class, user: admin,
                           action: 'create', namespace: 'org', name: 'bad_acl',
                           fields: fields,
                           read_roles: %w[nonexistent])
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('Unknown role')
    end
  end

  describe 'update action with ACL params' do
    before do
      call_tool(described_class, user: admin,
                action: 'create', namespace: 'org', name: 'locks',
                fields: fields)
    end

    it 'updates ACL columns' do
      response = call_tool(described_class, user: admin,
                           action: 'update', table: 'org.locks',
                           read_roles: %w[member])
      expect(response_error?(response)).to be_falsey
      schema = SOT::Schema.first(namespace: 'org', name: 'locks')
      expect(schema.parsed_read_roles).to eq(%w[member])
    end
  end

  describe 'update action with field merge' do
    before do
      call_tool(described_class, user: admin,
                action: 'create', namespace: 'org', name: 'tasks',
                fields: [
                  { 'name' => 'title', 'type' => 'string', 'description' => 'Task title', 'required' => true },
                  { 'name' => 'priority', 'type' => 'integer', 'description' => 'Priority level' }
                ])
    end

    it 'adds a new field via merge' do
      response = call_tool(described_class, user: admin,
                           action: 'update', table: 'org.tasks',
                           fields: [{ 'name' => 'notes', 'type' => 'text', 'description' => 'Notes' }])
      expect(response_error?(response)).to be false
      text = response_text(response)
      expect(text).to include('Added')
      expect(text).to include('notes')
      schema = SOT::Schema.first(namespace: 'org', name: 'tasks')
      expect(schema.parsed_fields.length).to eq(3)
    end

    it 'reports updated field properties in response' do
      response = call_tool(described_class, user: admin,
                           action: 'update', table: 'org.tasks',
                           fields: [{ 'name' => 'title', 'type' => 'string', 'description' => 'Updated title desc', 'required' => true }])
      expect(response_error?(response)).to be false
      text = response_text(response)
      expect(text).to include('Updated')
      expect(text).to include('title')
    end

    it 'removes fields with confirm_delete_fields and shows revert info' do
      response = call_tool(described_class, user: admin,
                           action: 'update', table: 'org.tasks',
                           confirm_delete_fields: ['priority'])
      expect(response_error?(response)).to be false
      text = response_text(response)
      expect(text).to include('Removed')
      expect(text).to include('priority')
      expect(text).to include('integer')
      schema = SOT::Schema.first(namespace: 'org', name: 'tasks')
      expect(schema.parsed_fields.length).to eq(1)
    end

    it 'errors when confirm_delete_fields lists nonexistent fields' do
      response = call_tool(described_class, user: admin,
                           action: 'update', table: 'org.tasks',
                           confirm_delete_fields: ['nonexistent'])
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('nonexistent')
    end
  end

  describe 'reorder_fields action' do
    before do
      call_tool(described_class, user: admin,
                action: 'create', namespace: 'org', name: 'tasks',
                fields: [
                  { 'name' => 'title', 'type' => 'string', 'required' => true },
                  { 'name' => 'priority', 'type' => 'integer' },
                  { 'name' => 'notes', 'type' => 'text' }
                ])
    end

    it 'reorders fields successfully' do
      response = call_tool(described_class, user: admin,
                           action: 'reorder_fields', table: 'org.tasks',
                           field_order: %w[notes title priority])
      expect(response_error?(response)).to be false
      text = response_text(response)
      expect(text).to include('Reordered')
      schema = SOT::Schema.first(namespace: 'org', name: 'tasks')
      expect(schema.parsed_fields.map { |f| f['name'] }).to eq(%w[notes title priority])
    end

    it 'errors when field names do not match' do
      response = call_tool(described_class, user: admin,
                           action: 'reorder_fields', table: 'org.tasks',
                           field_order: %w[title priority])
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('notes')
    end

    it 'reports no changes when order is identical' do
      response = call_tool(described_class, user: admin,
                           action: 'reorder_fields', table: 'org.tasks',
                           field_order: %w[title priority notes])
      expect(response_error?(response)).to be false
      expect(response_text(response)).to include('No changes')
    end

    it 'errors when table not found' do
      response = call_tool(described_class, user: admin,
                           action: 'reorder_fields', table: 'nonexistent',
                           field_order: %w[title])
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('not found')
    end
  end

  describe 'delete action' do
    before do
      call_tool(described_class, user: admin,
                action: 'create', namespace: 'org', name: 'locks',
                fields: fields)
    end

    it 'deletes a schema' do
      response = call_tool(described_class, user: admin,
                           action: 'delete', table: 'org.locks')
      expect(response_error?(response)).to be_falsey
      expect(SOT::Schema.count).to eq(0)
    end

    it 'returns error when schema has activity log entries' do
      schema = SOT::Schema.first(namespace: 'org', name: 'locks')
      SOT::MutationService.create(
        schema: schema,
        data: { 'title' => 'item' },
        user: admin
      )
      # Activity log now references this schema. Records cascade-delete, but activity_log FK blocks.
      # First delete all records so only activity_log FK remains
      SOT::Record.where(schema_id: schema.id).destroy

      response = call_tool(described_class, user: admin,
                           action: 'delete', table: 'org.locks')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('Cannot delete')
    end
  end
end
