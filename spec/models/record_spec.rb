require 'spec_helper'

RSpec.describe SOT::Record do
  let(:user) { create(:user) }
  let(:schema) { create(:entity_schema) }

  describe 'validations' do
    it 'requires schema_id' do
      record = SOT::Record.new(data: '{}', created_by: user.id, updated_by: user.id)
      expect(record.valid?).to be false
      expect(record.errors[:schema_id]).not_to be_empty
    end

    it 'requires data' do
      record = SOT::Record.new(schema_id: schema.id, data: nil, created_by: user.id, updated_by: user.id)
      expect(record.valid?).to be false
      expect(record.errors[:data]).not_to be_empty
    end

    it 'requires created_by' do
      record = SOT::Record.new(schema_id: schema.id, data: '{}', updated_by: user.id)
      expect(record.valid?).to be false
      expect(record.errors[:created_by]).not_to be_empty
    end

    it 'requires updated_by' do
      record = SOT::Record.new(schema_id: schema.id, data: '{}', created_by: user.id)
      expect(record.valid?).to be false
      expect(record.errors[:updated_by]).not_to be_empty
    end

    it 'saves a valid record' do
      record = create(:record)
      expect(record).to be_a(SOT::Record)
      expect(record.id).not_to be_nil
    end
  end

  describe '#parsed_data' do
    it 'parses the data JSON' do
      record = create(:record, data: JSON.generate({ 'title' => 'hello' }))
      expect(record.parsed_data).to eq({ 'title' => 'hello' })
    end
  end

  describe '#parsed_data=' do
    it 'serializes a hash to JSON' do
      record = create(:record)
      record.parsed_data = { 'title' => 'new' }
      expect(record.data).to eq('{"title":"new"}')
    end
  end

  describe 'associations' do
    it 'belongs to a schema' do
      record = create(:record, with_schema: schema)
      expect(record.schema).to eq(schema)
    end

    it 'belongs to a creator' do
      record = create(:record, with_user: user)
      expect(record.creator).to eq(user)
    end

    it 'belongs to an updater' do
      record = create(:record, with_user: user)
      expect(record.updater).to eq(user)
    end
  end

  describe 'timestamps' do
    it 'sets timestamps on create' do
      record = create(:record)
      expect(record.created_at).not_to be_nil
      expect(record.updated_at).not_to be_nil
    end
  end
end
