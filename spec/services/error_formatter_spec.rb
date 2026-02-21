require 'spec_helper'

RSpec.describe SOT::ErrorFormatter do
  let(:schema) { create(:entity_schema, :stateful, description: 'Tracks deployments') }

  describe '.format' do
    it 'includes the error message' do
      result = described_class.format('Something went wrong')
      expect(result).to include('ERROR: Something went wrong')
    end

    it 'includes the feedback tip' do
      result = described_class.format('error')
      expect(result).to include('sot_feedback')
    end

    it 'includes schema context when provided' do
      result = described_class.format('error', schema: schema)
      expect(result).to include("Schema Context: #{schema.full_name}")
      expect(result).to include('Tracks deployments')
      expect(result).to include('title (string) (required)')
      expect(result).to include('count (integer)')
    end

    it 'includes valid states for stateful schemas' do
      result = described_class.format('error', schema: schema)
      expect(result).to include('Valid states:')
      expect(result).to include('open')
      expect(result).to include('closed')
    end

    it 'does not include states for stateless schemas' do
      stateless = create(:entity_schema)
      result = described_class.format('error', schema: stateless)
      expect(result).not_to include('Valid states:')
    end

    it 'includes record context when provided' do
      record = create(:record, with_schema: schema, state: 'open')
      result = described_class.format('error', schema: schema, record: record)
      expect(result).to include('Current record state: open')
      expect(result).to include('Current data:')
    end

    it 'includes hint when provided' do
      result = described_class.format('error', hint: 'Try using sot_list_entities first')
      expect(result).to include('Hint: Try using sot_list_entities first')
    end

    it 'works with minimal arguments' do
      result = described_class.format('simple error')
      expect(result).to include('ERROR: simple error')
      expect(result).to include('sot_feedback')
    end
  end
end
