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
      expect(response_text(response)).to include("Created entity type 'org.locks'")
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
                           action: 'update', entity: 'org.locks',
                           description: 'Updated description')
      expect(response_error?(response)).to be_falsey
      expect(SOT::Schema.first.description).to eq('Updated description')
    end

    it 'returns error for unknown entity' do
      response = call_tool(described_class, user: admin,
                           action: 'update', entity: 'nonexistent')
      expect(response_error?(response)).to be true
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
                           action: 'delete', entity: 'org.locks')
      expect(response_error?(response)).to be_falsey
      expect(SOT::Schema.count).to eq(0)
    end

    it 'returns error when schema has activity log entries' do
      schema = SOT::Schema.first(namespace: 'org', name: 'locks')
      user_pair = SOT::User.create_with_token(name: 'worker')
      SOT::MutationService.create(
        schema: schema,
        data: { 'title' => 'item' },
        user: user_pair.first
      )
      # Activity log now references this schema. Records cascade-delete, but activity_log FK blocks.
      # First delete all records so only activity_log FK remains
      SOT::Record.where(schema_id: schema.id).destroy

      response = call_tool(described_class, user: admin,
                           action: 'delete', entity: 'org.locks')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('Cannot delete')
    end
  end
end
