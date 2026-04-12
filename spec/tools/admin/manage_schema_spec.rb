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
