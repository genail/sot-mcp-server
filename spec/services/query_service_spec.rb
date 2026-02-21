require 'spec_helper'

RSpec.describe SOT::QueryService do
  let(:user) { create(:user) }
  let(:schema) { create(:entity_schema, :stateful) }

  def create_record(data: { 'title' => 'Test', 'count' => '1' }, state: 'open')
    SOT::MutationService.create(schema: schema, data: data, state: state, user: user)
  end

  describe '.list' do
    it 'returns all records for a schema' do
      create_record
      create_record(data: { 'title' => 'Other' })
      expect(described_class.list(schema).length).to eq(2)
    end

    it 'filters by state' do
      create_record(state: 'open')
      create_record(state: 'closed', data: { 'title' => 'Closed one' })
      results = described_class.list(schema, state: 'open')
      expect(results.length).to eq(1)
    end

    it 'filters by data field' do
      create_record(data: { 'title' => 'Alpha' })
      create_record(data: { 'title' => 'Beta' })
      results = described_class.list(schema, filters: { 'title' => 'Alpha' })
      expect(results.length).to eq(1)
      expect(results.first.parsed_data['title']).to eq('Alpha')
    end

    it 'supports pagination with limit and offset' do
      5.times { |i| create_record(data: { 'title' => "Item #{i}" }) }
      page1 = described_class.list(schema, limit: 2, offset: 0)
      page2 = described_class.list(schema, limit: 2, offset: 2)
      expect(page1.length).to eq(2)
      expect(page2.length).to eq(2)
      expect(page1.map(&:id) & page2.map(&:id)).to be_empty
    end

    it 'returns empty array when no records match' do
      expect(described_class.list(schema)).to eq([])
    end

    it 'combines state and field filters' do
      create_record(data: { 'title' => 'Match' }, state: 'open')
      create_record(data: { 'title' => 'Match' }, state: 'closed')
      create_record(data: { 'title' => 'NoMatch' }, state: 'open')
      results = described_class.list(schema, filters: { 'title' => 'Match' }, state: 'open')
      expect(results.length).to eq(1)
    end
  end

  describe '.count' do
    it 'counts all records for a schema' do
      3.times { create_record(data: { 'title' => "Item #{_1}" }) }
      expect(described_class.count(schema)).to eq(3)
    end

    it 'counts with filters' do
      create_record(data: { 'title' => 'A' })
      create_record(data: { 'title' => 'B' })
      expect(described_class.count(schema, filters: { 'title' => 'A' })).to eq(1)
    end
  end

  describe '.find' do
    it 'finds a record by id within a schema' do
      record = create_record
      expect(described_class.find(schema, record.id)).to eq(record)
    end

    it 'returns nil for unknown id' do
      expect(described_class.find(schema, 99999)).to be_nil
    end

    it 'returns nil if record belongs to a different schema' do
      other_schema = create(:entity_schema)
      record = create(:record, with_schema: other_schema)
      expect(described_class.find(schema, record.id)).to be_nil
    end
  end
end
