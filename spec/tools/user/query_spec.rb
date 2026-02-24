require 'spec_helper'

RSpec.describe SOT::Tools::User::Query, type: :tool do
  let(:user) { create(:user) }
  let(:schema) { create(:table_schema, :stateful, namespace: 'org', name: 'locks') }

  before do
    SOT::MutationService.create(schema: schema, data: { 'title' => 'Alpha' }, state: 'open', user: user)
    SOT::MutationService.create(schema: schema, data: { 'title' => 'Beta' }, state: 'closed', user: user)
  end

  describe '.call' do
    it 'returns records for a table' do
      response = call_tool(described_class, user: user, table: 'org.locks')
      text = response_text(response)
      expect(text).to include('Alpha')
      expect(text).to include('Beta')
      expect(text).to include('Showing 1-2 of 2 record(s)')
    end

    it 'filters by state' do
      response = call_tool(described_class, user: user, table: 'org.locks', state: 'open')
      text = response_text(response)
      expect(text).to include('Alpha')
      expect(text).not_to include('Beta')
    end

    it 'filters by data field' do
      response = call_tool(described_class, user: user, table: 'org.locks', filters: { 'title' => 'Beta' })
      text = response_text(response)
      expect(text).to include('Beta')
      expect(text).not_to include('Alpha')
    end

    it 'returns error for unknown table' do
      response = call_tool(described_class, user: user, table: 'nonexistent')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include("not found")
      expect(response_text(response)).to include('sot_describe_tables')
    end

    it 'returns error for unknown filter field' do
      response = call_tool(described_class, user: user, table: 'org.locks', filters: { 'bad_field' => 'x' })
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('Unknown filter fields')
      expect(response_text(response)).to include('bad_field')
    end

    it 'handles no matching records' do
      response = call_tool(described_class, user: user, table: 'org.locks', state: 'archived')
      text = response_text(response)
      expect(text).to include('No records found')
    end

    it 'fetches a single record by ID' do
      record = SOT::Record.order(:id).first
      response = call_tool(described_class, user: user, table: 'org.locks', record_id: record.id)
      text = response_text(response)
      expect(text).to include("Record ##{record.id}")
      expect(text).to include('Alpha')
    end

    it 'returns error for unknown record ID' do
      response = call_tool(described_class, user: user, table: 'org.locks', record_id: 99999)
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('not found')
    end

    it 'searches by single term' do
      response = call_tool(described_class, user: user, table: 'org.locks', search: 'alpha')
      text = response_text(response)
      expect(text).to include('Alpha')
      expect(text).not_to include('Beta')
    end

    it 'searches by multiple terms (AND)' do
      SOT::MutationService.create(schema: schema, data: { 'title' => 'Alpha Gamma' }, state: 'open', user: user)
      response = call_tool(described_class, user: user, table: 'org.locks', search: ['alpha', 'gamma'])
      text = response_text(response)
      expect(text).to include('Alpha Gamma')
      expect(text).to include('Showing 1-1 of 1')
    end

    it 'returns no records when search has no matches' do
      response = call_tool(described_class, user: user, table: 'org.locks', search: 'nonexistent')
      text = response_text(response)
      expect(text).to include('No records found')
    end
  end
end
