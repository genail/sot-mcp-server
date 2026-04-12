require 'spec_helper'

RSpec.describe SOT::Schema do
  describe 'validations' do
    it 'requires namespace' do
      schema = build(:table_schema, namespace: nil)
      expect(schema.valid?).to be false
    end

    it 'requires name' do
      schema = build(:table_schema, name: nil)
      expect(schema.valid?).to be false
    end

    it 'requires fields' do
      schema = build(:table_schema, fields: nil)
      expect(schema.valid?).to be false
    end

    it 'requires lowercase alphanumeric namespace' do
      schema = build(:table_schema, namespace: 'My-Namespace')
      expect(schema.valid?).to be false
    end

    it 'requires lowercase alphanumeric name' do
      schema = build(:table_schema, name: 'My-Entity')
      expect(schema.valid?).to be false
    end

    it 'allows underscores in namespace and name' do
      schema = build(:table_schema, namespace: 'my_org', name: 'deploy_targets')
      expect(schema.valid?).to be true
    end

    it 'requires unique namespace + name pair' do
      create(:table_schema, namespace: 'org', name: 'locks')
      duplicate = build(:table_schema, namespace: 'org', name: 'locks')
      expect(duplicate.valid?).to be false
    end

    it 'allows same name in different namespaces' do
      create(:table_schema, namespace: 'org', name: 'locks')
      other = build(:table_schema, namespace: 'project', name: 'locks')
      expect(other.valid?).to be true
    end
  end

  describe '#full_name' do
    it 'returns namespace.name' do
      schema = build(:table_schema, namespace: 'org', name: 'locks')
      expect(schema.full_name).to eq('org.locks')
    end
  end

  describe '#parsed_fields' do
    it 'parses the fields JSON' do
      schema = create(:table_schema)
      fields = schema.parsed_fields
      expect(fields).to be_an(Array)
      expect(fields.first['name']).to eq('title')
    end
  end

  describe '#parsed_states' do
    it 'returns nil for stateless schemas' do
      schema = create(:table_schema)
      expect(schema.parsed_states).to be_nil
    end

    it 'parses the states JSON for stateful schemas' do
      schema = create(:table_schema, :stateful)
      states = schema.parsed_states
      expect(states).to be_an(Array)
      expect(states.first['name']).to eq('open')
    end
  end

  describe '#stateful?' do
    it 'returns false for stateless schemas' do
      expect(create(:table_schema).stateful?).to be false
    end

    it 'returns true for stateful schemas' do
      expect(create(:table_schema, :stateful).stateful?).to be true
    end
  end

  describe '#valid_state?' do
    it 'returns true for any state on stateless schemas' do
      schema = create(:table_schema)
      expect(schema.valid_state?('anything')).to be true
    end

    it 'returns true for valid states on stateful schemas' do
      schema = create(:table_schema, :stateful)
      expect(schema.valid_state?('open')).to be true
      expect(schema.valid_state?('closed')).to be true
    end

    it 'returns false for invalid states on stateful schemas' do
      schema = create(:table_schema, :stateful)
      expect(schema.valid_state?('nonexistent')).to be false
    end
  end

  describe '#required_field_names' do
    it 'returns names of required fields' do
      schema = create(:table_schema)
      expect(schema.required_field_names).to eq(['title'])
    end
  end

  describe '#all_field_names' do
    it 'returns all field names' do
      schema = create(:table_schema)
      expect(schema.all_field_names).to contain_exactly('title', 'count')
    end
  end

  describe '#parsed_read_roles' do
    it 'parses the JSON array' do
      schema = create(:table_schema, read_roles: JSON.generate(%w[admin member]))
      expect(schema.parsed_read_roles).to eq(%w[admin member])
    end

    it 'returns empty array for empty JSON array' do
      schema = create(:table_schema, read_roles: '[]')
      expect(schema.parsed_read_roles).to eq([])
    end
  end

  describe '#parsed_create_roles' do
    it 'parses the JSON array' do
      schema = create(:table_schema, create_roles: JSON.generate(%w[member]))
      expect(schema.parsed_create_roles).to eq(%w[member])
    end
  end

  describe '#parsed_update_roles' do
    it 'parses the JSON array' do
      schema = create(:table_schema, update_roles: JSON.generate(%w[admin]))
      expect(schema.parsed_update_roles).to eq(%w[admin])
    end
  end

  describe '#parsed_delete_roles' do
    it 'parses the JSON array' do
      schema = create(:table_schema, delete_roles: '[]')
      expect(schema.parsed_delete_roles).to eq([])
    end
  end

  describe '#roles_for_action' do
    let(:schema) do
      create(:table_schema,
             read_roles: JSON.generate(%w[member]),
             create_roles: JSON.generate(%w[admin]),
             update_roles: JSON.generate(%w[admin member]),
             delete_roles: '[]')
    end

    it 'returns correct roles for :read' do
      expect(schema.roles_for_action(:read)).to eq(%w[member])
    end

    it 'returns correct roles for :create' do
      expect(schema.roles_for_action(:create)).to eq(%w[admin])
    end

    it 'returns correct roles for :update' do
      expect(schema.roles_for_action(:update)).to eq(%w[admin member])
    end

    it 'returns correct roles for :delete' do
      expect(schema.roles_for_action(:delete)).to eq([])
    end

    it 'accepts string action names' do
      expect(schema.roles_for_action('read')).to eq(%w[member])
    end

    it 'returns empty array for invalid action' do
      expect(schema.roles_for_action(:unknown)).to eq([])
    end
  end

  describe '#default_state' do
    it 'returns nil for stateless schemas' do
      expect(create(:table_schema).default_state).to be_nil
    end

    it 'returns the first state for stateful schemas' do
      expect(create(:table_schema, :stateful).default_state).to eq('open')
    end
  end
end
