require 'spec_helper'

RSpec.describe SOT::QueryService do
  let(:user) { create(:user) }
  let(:schema) { create(:table_schema, :stateful) }

  def create_record(data: { 'title' => 'Test', 'count' => '1' }, state: 'open')
    SOT::MutationService.create(schema: schema, data: data, state: state, user: user)
  end

  describe '.list' do
    it 'returns all records for a schema' do
      create_record
      create_record(data: { 'title' => 'Other' })
      expect(described_class.list([schema.id]).length).to eq(2)
    end

    it 'filters by state' do
      create_record(state: 'open')
      create_record(state: 'closed', data: { 'title' => 'Closed one' })
      results = described_class.list([schema.id], state: 'open')
      expect(results.length).to eq(1)
    end

    it 'filters by data field' do
      create_record(data: { 'title' => 'Alpha' })
      create_record(data: { 'title' => 'Beta' })
      results = described_class.list([schema.id], filters: { 'title' => 'Alpha' })
      expect(results.length).to eq(1)
      expect(results.first.parsed_data['title']).to eq('Alpha')
    end

    it 'supports pagination with limit and offset' do
      5.times { |i| create_record(data: { 'title' => "Item #{i}" }) }
      page1 = described_class.list([schema.id], limit: 2, offset: 0)
      page2 = described_class.list([schema.id], limit: 2, offset: 2)
      expect(page1.length).to eq(2)
      expect(page2.length).to eq(2)
      expect(page1.map(&:id) & page2.map(&:id)).to be_empty
    end

    it 'returns empty array when no records match' do
      expect(described_class.list([schema.id])).to eq([])
    end

    it 'combines state and field filters' do
      create_record(data: { 'title' => 'Match' }, state: 'open')
      create_record(data: { 'title' => 'Match' }, state: 'closed')
      create_record(data: { 'title' => 'NoMatch' }, state: 'open')
      results = described_class.list([schema.id], filters: { 'title' => 'Match' }, state: 'open')
      expect(results.length).to eq(1)
    end

    it 'searches by single term (case-insensitive)' do
      create_record(data: { 'title' => 'Staging DB' })
      create_record(data: { 'title' => 'Production DB' })
      results = described_class.list([schema.id], search: ['staging'])
      expect(results.length).to eq(1)
      expect(results.first.parsed_data['title']).to eq('Staging DB')
    end

    it 'searches by multiple terms with OR logic ranked by relevance' do
      create_record(data: { 'title' => 'Staging DB migration' })
      create_record(data: { 'title' => 'Staging API deploy' })
      create_record(data: { 'title' => 'Production DB migration' })
      results = described_class.list([schema.id], search: ['staging', 'migration'])
      expect(results.length).to eq(3)
      # Record matching both terms ranked first
      expect(results.first.parsed_data['title']).to eq('Staging DB migration')
    end

    it 'splits a single search string into terms' do
      create_record(data: { 'title' => 'Staging DB migration' })
      create_record(data: { 'title' => 'Staging API deploy' })
      results = described_class.list([schema.id], search: 'staging migration')
      expect(results.length).to eq(2)
      expect(results.first.parsed_data['title']).to eq('Staging DB migration')
    end

    it 'filters stopwords from search terms' do
      create_record(data: { 'title' => 'Staging DB' })
      create_record(data: { 'title' => 'Production DB' })
      results = described_class.list([schema.id], search: 'the staging')
      expect(results.length).to eq(1)
      expect(results.first.parsed_data['title']).to eq('Staging DB')
    end

    it 'combines search with filters and state' do
      create_record(data: { 'title' => 'Staging DB' }, state: 'open')
      create_record(data: { 'title' => 'Staging DB' }, state: 'closed')
      results = described_class.list([schema.id], search: ['staging'], state: 'open')
      expect(results.length).to eq(1)
    end
  end

  describe '.list with multiple schemas' do
    let(:schema2) { create(:table_schema, :stateful, namespace: 'org', name: 'docs') }

    it 'returns records from multiple schemas' do
      create_record(data: { 'title' => 'Lock Alpha' })
      SOT::MutationService.create(schema: schema2, data: { 'title' => 'Doc Beta' }, state: 'open', user: user)
      results = described_class.list([schema.id, schema2.id])
      expect(results.length).to eq(2)
    end

    it 'filters by state across multiple schemas' do
      create_record(data: { 'title' => 'Lock Open' }, state: 'open')
      SOT::MutationService.create(schema: schema2, data: { 'title' => 'Doc Open' }, state: 'open', user: user)
      SOT::MutationService.create(schema: schema2, data: { 'title' => 'Doc Closed' }, state: 'closed', user: user)
      results = described_class.list([schema.id, schema2.id], state: 'open')
      expect(results.length).to eq(2)
    end

    it 'searches across multiple schemas with relevance' do
      create_record(data: { 'title' => 'Lock Alpha' })
      SOT::MutationService.create(schema: schema2, data: { 'title' => 'Doc Alpha Beta' }, state: 'open', user: user)
      results = described_class.list([schema.id, schema2.id], search: ['alpha', 'beta'])
      expect(results.length).to eq(2)
      # Doc Alpha Beta matches both terms, should rank first
      expect(results.first.parsed_data['title']).to eq('Doc Alpha Beta')
    end

    it 'paginates across combined set' do
      3.times { |i| create_record(data: { 'title' => "Lock #{i}" }) }
      2.times { |i| SOT::MutationService.create(schema: schema2, data: { 'title' => "Doc #{i}" }, state: 'open', user: user) }
      results = described_class.list([schema.id, schema2.id], limit: 3, offset: 0)
      expect(results.length).to eq(3)
      all_results = described_class.list([schema.id, schema2.id])
      expect(all_results.length).to eq(5)
    end
  end

  describe '.count' do
    it 'counts all records for a schema' do
      3.times { create_record(data: { 'title' => "Item #{_1}" }) }
      expect(described_class.count([schema.id])).to eq(3)
    end

    it 'counts with filters' do
      create_record(data: { 'title' => 'A' })
      create_record(data: { 'title' => 'B' })
      expect(described_class.count([schema.id], filters: { 'title' => 'A' })).to eq(1)
    end

    it 'counts across multiple schemas' do
      schema2 = create(:table_schema, :stateful, namespace: 'org', name: 'docs')
      create_record
      SOT::MutationService.create(schema: schema2, data: { 'title' => 'Doc' }, state: 'open', user: user)
      expect(described_class.count([schema.id, schema2.id])).to eq(2)
    end
  end

  describe '.find' do
    it 'finds a record by id' do
      record = create_record
      expect(described_class.find(record.id)).to eq(record)
    end

    it 'returns nil for unknown id' do
      expect(described_class.find(99999)).to be_nil
    end
  end
end
