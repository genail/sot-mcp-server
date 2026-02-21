require 'spec_helper'

RSpec.describe SOT::Schema do
  describe 'validations' do
    it 'requires namespace' do
      schema = build(:entity_schema, namespace: nil)
      expect(schema.valid?).to be false
    end

    it 'requires name' do
      schema = build(:entity_schema, name: nil)
      expect(schema.valid?).to be false
    end

    it 'requires fields' do
      schema = build(:entity_schema, fields: nil)
      expect(schema.valid?).to be false
    end

    it 'requires lowercase alphanumeric namespace' do
      schema = build(:entity_schema, namespace: 'My-Namespace')
      expect(schema.valid?).to be false
    end

    it 'requires lowercase alphanumeric name' do
      schema = build(:entity_schema, name: 'My-Entity')
      expect(schema.valid?).to be false
    end

    it 'allows underscores in namespace and name' do
      schema = build(:entity_schema, namespace: 'my_org', name: 'deploy_targets')
      expect(schema.valid?).to be true
    end

    it 'requires unique namespace + name pair' do
      create(:entity_schema, namespace: 'org', name: 'locks')
      duplicate = build(:entity_schema, namespace: 'org', name: 'locks')
      expect(duplicate.valid?).to be false
    end

    it 'allows same name in different namespaces' do
      create(:entity_schema, namespace: 'org', name: 'locks')
      other = build(:entity_schema, namespace: 'project', name: 'locks')
      expect(other.valid?).to be true
    end
  end

  describe '#full_name' do
    it 'returns namespace.name' do
      schema = build(:entity_schema, namespace: 'org', name: 'locks')
      expect(schema.full_name).to eq('org.locks')
    end
  end

  describe '#parsed_fields' do
    it 'parses the fields JSON' do
      schema = create(:entity_schema)
      fields = schema.parsed_fields
      expect(fields).to be_an(Array)
      expect(fields.first['name']).to eq('title')
    end
  end

  describe '#parsed_states' do
    it 'returns nil for stateless schemas' do
      schema = create(:entity_schema)
      expect(schema.parsed_states).to be_nil
    end

    it 'parses the states JSON for stateful schemas' do
      schema = create(:entity_schema, :stateful)
      states = schema.parsed_states
      expect(states).to be_an(Array)
      expect(states.first['name']).to eq('open')
    end
  end

  describe '#stateful?' do
    it 'returns false for stateless schemas' do
      expect(create(:entity_schema).stateful?).to be false
    end

    it 'returns true for stateful schemas' do
      expect(create(:entity_schema, :stateful).stateful?).to be true
    end
  end

  describe '#valid_state?' do
    it 'returns true for any state on stateless schemas' do
      schema = create(:entity_schema)
      expect(schema.valid_state?('anything')).to be true
    end

    it 'returns true for valid states on stateful schemas' do
      schema = create(:entity_schema, :stateful)
      expect(schema.valid_state?('open')).to be true
      expect(schema.valid_state?('closed')).to be true
    end

    it 'returns false for invalid states on stateful schemas' do
      schema = create(:entity_schema, :stateful)
      expect(schema.valid_state?('nonexistent')).to be false
    end
  end

  describe '#required_field_names' do
    it 'returns names of required fields' do
      schema = create(:entity_schema)
      expect(schema.required_field_names).to eq(['title'])
    end
  end

  describe '#all_field_names' do
    it 'returns all field names' do
      schema = create(:entity_schema)
      expect(schema.all_field_names).to contain_exactly('title', 'count')
    end
  end

  describe '#default_state' do
    it 'returns nil for stateless schemas' do
      expect(create(:entity_schema).default_state).to be_nil
    end

    it 'returns the first state for stateful schemas' do
      expect(create(:entity_schema, :stateful).default_state).to eq('open')
    end
  end
end
