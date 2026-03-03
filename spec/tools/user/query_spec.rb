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
      expect(response_text(response)).to include('bad_field')
      expect(response_text(response)).to include('not found in table')
    end

    it 'handles no matching records' do
      response = call_tool(described_class, user: user, table: 'org.locks', state: 'archived')
      text = response_text(response)
      expect(text).to include('No records found')
    end

    it 'fetches a single record by ID with version' do
      record = SOT::Record.order(:id).first
      response = call_tool(described_class, user: user, table: 'org.locks', record_id: record.id)
      text = response_text(response)
      expect(text).to include("Record ##{record.id} (v1)")
      expect(text).to include('Alpha')
      expect(text).to include('in org.locks')
    end

    it 'includes version in list results' do
      response = call_tool(described_class, user: user, table: 'org.locks')
      text = response_text(response)
      expect(text).to include('(v1)')
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

    it 'searches by multiple terms with OR logic ranked by relevance' do
      SOT::MutationService.create(schema: schema, data: { 'title' => 'Alpha Gamma' }, state: 'open', user: user)
      response = call_tool(described_class, user: user, table: 'org.locks', search: ['alpha', 'gamma'])
      text = response_text(response)
      # Alpha Gamma matches both terms (highest relevance), Alpha matches one
      expect(text).to include('Showing 1-2 of 2')
      lines = text.split("\n").reject(&:empty?)
      # First result should be the one matching both terms
      expect(lines[1]).to include('Alpha Gamma')
    end

    it 'returns no records when search has no matches' do
      response = call_tool(described_class, user: user, table: 'org.locks', search: 'nonexistent')
      text = response_text(response)
      expect(text).to include('No records found')
    end

    it 'does not show table name in single-table list results' do
      response = call_tool(described_class, user: user, table: 'org.locks')
      text = response_text(response)
      expect(text).not_to include('in org.locks:')
    end
  end

  describe 'multi-table queries' do
    let(:schema2) { create(:table_schema, :stateful, namespace: 'org', name: 'docs') }

    before do
      SOT::MutationService.create(schema: schema2, data: { 'title' => 'Doc One' }, state: 'open', user: user)
    end

    it 'queries across multiple tables with array param' do
      response = call_tool(described_class, user: user, table: ['org.locks', 'org.docs'])
      text = response_text(response)
      expect(text).to include('Alpha')
      expect(text).to include('Doc One')
    end

    it 'shows table name per record in multi-table output' do
      response = call_tool(described_class, user: user, table: ['org.locks', 'org.docs'])
      text = response_text(response)
      expect(text).to include('in org.locks')
      expect(text).to include('in org.docs')
    end

    it 'includes all tables in pagination header' do
      response = call_tool(described_class, user: user, table: ['org.locks', 'org.docs'])
      text = response_text(response)
      expect(text).to include('org.locks, org.docs')
    end

    it 'returns error when any table not found' do
      response = call_tool(described_class, user: user, table: ['org.locks', 'nonexistent'])
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('nonexistent')
      expect(response_text(response)).to include('not found')
    end

    it 'returns error when filter field missing from one table' do
      schema3 = create(:table_schema, namespace: 'org', name: 'metrics',
                       fields: JSON.generate([{ 'name' => 'value', 'type' => 'integer' }]))
      response = call_tool(described_class, user: user, table: ['org.locks', 'org.metrics'], filters: { 'title' => 'x' })
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('title')
      expect(response_text(response)).to include('org.metrics')
    end

    it 'allows filters that exist in all tables' do
      response = call_tool(described_class, user: user, table: ['org.locks', 'org.docs'], filters: { 'title' => 'Alpha' })
      expect(response_error?(response)).to be false
      text = response_text(response)
      expect(text).to include('Alpha')
    end

    it 'returns error when state filter applied to stateless table' do
      create(:table_schema, namespace: 'org', name: 'notes')
      response = call_tool(described_class, user: user, table: ['org.locks', 'org.notes'], state: 'open')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('stateless')
      expect(response_text(response)).to include('org.notes')
    end

    it 'returns error when state not defined in one of the tables' do
      # schema2 (:stateful) has open/closed/archived, but not 'pending'
      response = call_tool(described_class, user: user, table: ['org.locks', 'org.docs'], state: 'pending')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('pending')
      expect(response_text(response)).to include('not valid')
    end

    it 'filters by state across multiple tables' do
      response = call_tool(described_class, user: user, table: ['org.locks', 'org.docs'], state: 'open')
      text = response_text(response)
      expect(text).to include('Alpha')
      expect(text).to include('Doc One')
      expect(text).not_to include('Beta')
    end

    it 'searches across multiple tables' do
      response = call_tool(described_class, user: user, table: ['org.locks', 'org.docs'], search: 'alpha')
      text = response_text(response)
      expect(text).to include('Alpha')
      expect(text).not_to include('Doc One')
    end

    it 'deduplicates table names' do
      response = call_tool(described_class, user: user, table: ['org.locks', 'org.locks'])
      text = response_text(response)
      expect(text).to include('Showing 1-2 of 2')
    end
  end

  describe 'record_id lookup' do
    it 'finds record regardless of which table is specified' do
      record = SOT::Record.order(:id).first
      schema2 = create(:table_schema, namespace: 'org', name: 'docs')
      response = call_tool(described_class, user: user, table: 'org.docs', record_id: record.id)
      text = response_text(response)
      expect(text).to include("Record ##{record.id}")
      expect(text).to include('in org.locks')
    end

    it 'includes table name in record_id output' do
      record = SOT::Record.order(:id).first
      response = call_tool(described_class, user: user, table: 'org.locks', record_id: record.id)
      text = response_text(response)
      expect(text).to include('in org.locks')
    end
  end
end
