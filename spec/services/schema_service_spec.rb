require 'spec_helper'

RSpec.describe SOT::SchemaService do
  let(:valid_fields) do
    [{ 'name' => 'title', 'type' => 'string', 'description' => 'Title', 'required' => true }]
  end

  let(:valid_states) do
    [{ 'name' => 'open', 'description' => 'Open' }, { 'name' => 'closed', 'description' => 'Closed' }]
  end

  describe '.validate_fields!' do
    it 'accepts valid fields' do
      expect { described_class.validate_fields!(valid_fields) }.not_to raise_error
    end

    it 'rejects non-array' do
      expect { described_class.validate_fields!('not an array') }.to raise_error(ArgumentError, /must be an array/)
    end

    it 'rejects empty array' do
      expect { described_class.validate_fields!([]) }.to raise_error(ArgumentError, /cannot be empty/)
    end

    it 'rejects field without name' do
      expect { described_class.validate_fields!([{ 'type' => 'string' }]) }.to raise_error(ArgumentError, /must have 'name'/)
    end

    it 'rejects field without type' do
      expect { described_class.validate_fields!([{ 'name' => 'x' }]) }.to raise_error(ArgumentError, /must have 'type'/)
    end

    it 'rejects invalid type' do
      expect { described_class.validate_fields!([{ 'name' => 'x', 'type' => 'invalid' }]) }.to raise_error(ArgumentError, /invalid/)
    end

    it 'accepts symbol-keyed fields (from MCP gem)' do
      symbol_fields = [{ name: 'title', type: 'string', description: 'Title', required: true }]
      expect { described_class.validate_fields!(symbol_fields) }.not_to raise_error
    end
  end

  describe '.validate_states!' do
    it 'accepts nil (stateless)' do
      expect { described_class.validate_states!(nil) }.not_to raise_error
    end

    it 'accepts valid states' do
      expect { described_class.validate_states!(valid_states) }.not_to raise_error
    end

    it 'rejects non-array' do
      expect { described_class.validate_states!('not an array') }.to raise_error(ArgumentError)
    end

    it 'rejects empty array' do
      expect { described_class.validate_states!([]) }.to raise_error(ArgumentError, /cannot be empty/)
    end

    it 'rejects state without name' do
      expect { described_class.validate_states!([{ 'description' => 'x' }]) }.to raise_error(ArgumentError, /must have 'name'/)
    end

    it 'accepts symbol-keyed states (from MCP gem)' do
      symbol_states = [{ name: 'open', description: 'Open' }]
      expect { described_class.validate_states!(symbol_states) }.not_to raise_error
    end
  end

  describe '.create' do
    it 'creates a schema' do
      schema = described_class.create(
        namespace: 'org',
        name: 'locks',
        description: 'Resource locks',
        fields: valid_fields,
        states: valid_states
      )
      expect(schema).to be_a(SOT::Schema)
      expect(schema.full_name).to eq('org.locks')
      expect(schema.description).to eq('Resource locks')
      expect(schema.parsed_fields.length).to eq(1)
      expect(schema.parsed_states.length).to eq(2)
    end

    it 'creates a stateless schema' do
      schema = described_class.create(
        namespace: 'org',
        name: 'docs',
        fields: valid_fields
      )
      expect(schema.stateful?).to be false
    end

    it 'raises on invalid fields' do
      expect {
        described_class.create(namespace: 'org', name: 'bad', fields: [])
      }.to raise_error(ArgumentError)
    end

    it 'creates a schema with symbol-keyed fields and states' do
      symbol_fields = [{ name: 'title', type: 'string', required: true }]
      symbol_states = [{ name: 'open', description: 'Open' }]
      schema = described_class.create(
        namespace: 'org', name: 'sym_test',
        fields: symbol_fields, states: symbol_states
      )
      expect(schema.parsed_fields.first['name']).to eq('title')
      expect(schema.parsed_states.first['name']).to eq('open')
    end
  end

  describe '.update' do
    let(:schema) { create(:table_schema) }

    it 'updates the description' do
      described_class.update(schema, description: 'New description')
      expect(schema.reload.description).to eq('New description')
    end

    it 'updates fields' do
      new_fields = [{ 'name' => 'body', 'type' => 'text', 'required' => false }]
      described_class.update(schema, fields: new_fields)
      expect(schema.reload.parsed_fields.first['name']).to eq('body')
    end

    it 'validates fields on update' do
      expect {
        described_class.update(schema, fields: [])
      }.to raise_error(ArgumentError)
    end
  end

  describe '.delete' do
    it 'deletes the schema' do
      schema = create(:table_schema)
      id = schema.id
      described_class.delete(schema)
      expect(SOT::Schema[id]).to be_nil
    end
  end

  describe '.resolve' do
    it 'resolves by full name (namespace.name)' do
      schema = create(:table_schema, namespace: 'org', name: 'locks')
      expect(described_class.resolve('org.locks')).to eq(schema)
    end

    it 'resolves by short name' do
      schema = create(:table_schema, name: 'locks')
      expect(described_class.resolve('locks')).to eq(schema)
    end

    it 'returns nil for unknown table' do
      expect(described_class.resolve('nonexistent')).to be_nil
    end

    it 'returns nil for nil input' do
      expect(described_class.resolve(nil)).to be_nil
    end

    it 'returns nil for empty input' do
      expect(described_class.resolve('')).to be_nil
    end
  end

  describe '.resolve_many' do
    it 'resolves multiple table names' do
      schema1 = create(:table_schema, namespace: 'org', name: 'locks')
      schema2 = create(:table_schema, namespace: 'org', name: 'docs')
      result = described_class.resolve_many(['org.locks', 'org.docs'])
      expect(result['org.locks']).to eq(schema1)
      expect(result['org.docs']).to eq(schema2)
    end

    it 'returns nil for unresolved names' do
      create(:table_schema, namespace: 'org', name: 'locks')
      result = described_class.resolve_many(['org.locks', 'nonexistent'])
      expect(result['org.locks']).to be_a(SOT::Schema)
      expect(result['nonexistent']).to be_nil
    end

    it 'returns empty hash for empty input' do
      expect(described_class.resolve_many([])).to eq({})
    end
  end

  describe '.validate_acl!' do
    it 'accepts valid role names' do
      expect {
        described_class.send(:validate_acl!, read_roles: ['admin', 'member'])
      }.not_to raise_error
    end

    it 'accepts empty arrays' do
      expect {
        described_class.send(:validate_acl!, read_roles: [], create_roles: [])
      }.not_to raise_error
    end

    it 'rejects unknown role names' do
      expect {
        described_class.send(:validate_acl!, read_roles: ['nonexistent'])
      }.to raise_error(ArgumentError, /Unknown role/)
    end

    it 'rejects non-array values' do
      expect {
        described_class.send(:validate_acl!, read_roles: 'member')
      }.to raise_error(ArgumentError, /must be an array/)
    end

    it 'rejects mixed valid and invalid role names' do
      expect {
        described_class.send(:validate_acl!, read_roles: ['member', 'fake'])
      }.to raise_error(ArgumentError, /Unknown role.*fake/)
    end

    it 'ignores non-ACL keys in attrs' do
      expect {
        described_class.send(:validate_acl!, description: 'test', fields: [])
      }.not_to raise_error
    end
  end

  describe 'ACL passthrough in .create' do
    it 'persists ACL columns on create' do
      schema = described_class.create(
        namespace: 'test', name: 'acl_test',
        fields: valid_fields,
        read_roles: ['member'], create_roles: ['admin']
      )
      expect(schema.parsed_read_roles).to eq(['member'])
      expect(schema.parsed_create_roles).to eq(['admin'])
      expect(schema.parsed_update_roles).to eq([])
      expect(schema.parsed_delete_roles).to eq([])
    end
  end

  describe 'ACL passthrough in .update' do
    it 'updates ACL columns' do
      schema = create(:table_schema)
      described_class.update(schema, read_roles: ['admin'])
      expect(schema.reload.parsed_read_roles).to eq(['admin'])
    end

    it 'does not change other ACL columns when updating one' do
      schema = create(:table_schema)
      original_create_roles = schema.parsed_create_roles
      described_class.update(schema, read_roles: ['admin'])
      expect(schema.reload.parsed_create_roles).to eq(original_create_roles)
    end
  end

  describe '.list' do
    it 'returns all schemas' do
      create(:table_schema, namespace: 'org', name: 'a')
      create(:table_schema, namespace: 'org', name: 'b')
      expect(described_class.list.length).to eq(2)
    end

    it 'filters by namespace' do
      create(:table_schema, namespace: 'org', name: 'a')
      create(:table_schema, namespace: 'project', name: 'b')
      expect(described_class.list(namespace: 'org').length).to eq(1)
    end
  end
end
