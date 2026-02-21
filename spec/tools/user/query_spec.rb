require 'spec_helper'

RSpec.describe SOT::Tools::User::Query, type: :tool do
  let(:user) { create(:user) }
  let(:schema) { create(:entity_schema, :stateful, namespace: 'org', name: 'locks') }

  before do
    SOT::MutationService.create(schema: schema, data: { 'title' => 'Alpha' }, state: 'open', user: user)
    SOT::MutationService.create(schema: schema, data: { 'title' => 'Beta' }, state: 'closed', user: user)
  end

  describe '.call' do
    it 'returns records for an entity' do
      response = call_tool(described_class, user: user, entity: 'org.locks')
      text = response_text(response)
      expect(text).to include('Alpha')
      expect(text).to include('Beta')
      expect(text).to include('Found 2 record(s)')
    end

    it 'filters by state' do
      response = call_tool(described_class, user: user, entity: 'org.locks', state: 'open')
      text = response_text(response)
      expect(text).to include('Alpha')
      expect(text).not_to include('Beta')
    end

    it 'filters by data field' do
      response = call_tool(described_class, user: user, entity: 'org.locks', filters: { 'title' => 'Beta' })
      text = response_text(response)
      expect(text).to include('Beta')
      expect(text).not_to include('Alpha')
    end

    it 'returns error for unknown entity type' do
      response = call_tool(described_class, user: user, entity: 'nonexistent')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include("not found")
      expect(response_text(response)).to include('sot_list_entities')
    end

    it 'returns error for unknown filter field' do
      response = call_tool(described_class, user: user, entity: 'org.locks', filters: { 'bad_field' => 'x' })
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('Unknown filter fields')
      expect(response_text(response)).to include('bad_field')
    end

    it 'handles no matching records' do
      response = call_tool(described_class, user: user, entity: 'org.locks', state: 'archived')
      text = response_text(response)
      expect(text).to include('No records found')
    end

    it 'fetches a single record by ID' do
      record = SOT::Record.order(:id).first
      response = call_tool(described_class, user: user, entity: 'org.locks', record_id: record.id)
      text = response_text(response)
      expect(text).to include("Record ##{record.id}")
      expect(text).to include('Alpha')
    end

    it 'returns error for unknown record ID' do
      response = call_tool(described_class, user: user, entity: 'org.locks', record_id: 99999)
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('not found')
    end
  end
end
