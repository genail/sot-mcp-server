require 'spec_helper'

RSpec.describe SOT::Tools::User::Mutate, type: :tool do
  let(:user) { create(:user) }
  let!(:schema) { create(:entity_schema, :stateful, namespace: 'org', name: 'locks', description: 'Resource locks') }

  describe 'create action' do
    it 'creates a record' do
      response = call_tool(described_class, user: user,
                           action: 'create', entity: 'org.locks', data: { 'title' => 'New' })
      expect(response_error?(response)).to be false
      text = response_text(response)
      expect(text).to include('Created record')
      expect(text).to include('New')
    end

    it 'returns error for unknown entity' do
      response = call_tool(described_class, user: user,
                           action: 'create', entity: 'nonexistent', data: { 'title' => 'x' })
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('not found')
    end

    it 'returns error for missing data' do
      response = call_tool(described_class, user: user,
                           action: 'create', entity: 'org.locks')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include("'data' is required")
    end

    it 'returns schema context on validation error' do
      response = call_tool(described_class, user: user,
                           action: 'create', entity: 'org.locks', data: { 'bad' => 'field' })
      expect(response_error?(response)).to be true
      text = response_text(response)
      expect(text).to include('Schema Context')
      expect(text).to include('Resource locks')
      expect(text).to include('sot_feedback')
    end
  end

  describe 'update action' do
    let(:record) do
      SOT::MutationService.create(schema: schema, data: { 'title' => 'Original' }, state: 'open', user: user)
    end

    it 'updates a record' do
      response = call_tool(described_class, user: user,
                           action: 'update', record_id: record.id, data: { 'title' => 'Updated' })
      expect(response_error?(response)).to be false
      expect(response_text(response)).to include('Updated')
    end

    it 'updates with passing preconditions' do
      response = call_tool(described_class, user: user,
                           action: 'update', record_id: record.id,
                           state: 'closed', preconditions: { 'state' => 'open' })
      expect(response_error?(response)).to be false
      expect(response_text(response)).to include('closed')
    end

    it 'returns error with schema context on precondition failure' do
      response = call_tool(described_class, user: user,
                           action: 'update', record_id: record.id,
                           state: 'closed', preconditions: { 'state' => 'closed' })
      expect(response_error?(response)).to be true
      text = response_text(response)
      expect(text).to include('Precondition failed')
      expect(text).to include('Schema Context')
      expect(text).to include('Current record state: open')
      expect(text).to include('sot_feedback')
    end

    it 'returns error for missing record_id' do
      response = call_tool(described_class, user: user,
                           action: 'update', data: { 'title' => 'x' })
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include("'record_id' is required")
    end

    it 'returns error for nonexistent record' do
      response = call_tool(described_class, user: user,
                           action: 'update', record_id: 99999)
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('not found')
    end
  end

  describe 'delete action' do
    let(:record) do
      SOT::MutationService.create(schema: schema, data: { 'title' => 'ToDelete' }, state: 'open', user: user)
    end

    it 'deletes a record' do
      response = call_tool(described_class, user: user,
                           action: 'delete', record_id: record.id)
      expect(response_error?(response)).to be false
      expect(response_text(response)).to include('Deleted')
    end

    it 'returns error on precondition failure' do
      response = call_tool(described_class, user: user,
                           action: 'delete', record_id: record.id,
                           preconditions: { 'state' => 'closed' })
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('Precondition failed')
    end
  end
end
