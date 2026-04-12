require 'spec_helper'

RSpec.describe SOT::PermissionService do
  let(:admin_user) { create(:user, :admin) }
  let(:member_user) { create(:user) }
  let(:custom_role) { SOT::Role.create(name: 'support') }
  let(:support_user) { create(:user, role_id: custom_role.id) }

  let(:open_schema) do
    create(:table_schema,
           read_roles: JSON.generate(%w[member support]),
           create_roles: JSON.generate(%w[member]),
           update_roles: JSON.generate(%w[member]),
           delete_roles: JSON.generate(%w[member]))
  end

  let(:restricted_schema) do
    create(:table_schema,
           read_roles: '[]',
           create_roles: '[]',
           update_roles: '[]',
           delete_roles: '[]')
  end

  describe '.can?' do
    it 'always returns true for admin' do
      expect(described_class.can?(admin_user, restricted_schema, :read)).to be true
      expect(described_class.can?(admin_user, restricted_schema, :create)).to be true
      expect(described_class.can?(admin_user, restricted_schema, :update)).to be true
      expect(described_class.can?(admin_user, restricted_schema, :delete)).to be true
    end

    it 'returns true when role is in schema ACL' do
      expect(described_class.can?(member_user, open_schema, :read)).to be true
      expect(described_class.can?(member_user, open_schema, :create)).to be true
    end

    it 'returns false when role is not in schema ACL' do
      expect(described_class.can?(member_user, restricted_schema, :read)).to be false
      expect(described_class.can?(member_user, restricted_schema, :create)).to be false
    end

    it 'checks per-action ACL independently' do
      expect(described_class.can?(support_user, open_schema, :read)).to be true
      expect(described_class.can?(support_user, open_schema, :create)).to be false
    end

    it 'raises on invalid action' do
      expect { described_class.can?(member_user, open_schema, :admin) }.to raise_error(ArgumentError)
    end
  end

  describe '.authorize!' do
    it 'does not raise when permitted' do
      expect { described_class.authorize!(member_user, open_schema, :read) }.not_to raise_error
    end

    it 'raises PermissionDenied when denied' do
      expect {
        described_class.authorize!(member_user, restricted_schema, :read)
      }.to raise_error(SOT::PermissionService::PermissionDenied)
    end

    it 'does not raise for admin on restricted schema' do
      expect { described_class.authorize!(admin_user, restricted_schema, :delete) }.not_to raise_error
    end
  end

  describe '.readable_schemas' do
    before do
      open_schema
      restricted_schema
    end

    it 'returns all schemas for admin' do
      schemas = described_class.readable_schemas(admin_user)
      expect(schemas.map(&:id)).to include(open_schema.id, restricted_schema.id)
    end

    it 'returns only permitted schemas for member' do
      schemas = described_class.readable_schemas(member_user)
      expect(schemas.map(&:id)).to include(open_schema.id)
      expect(schemas.map(&:id)).not_to include(restricted_schema.id)
    end
  end

  describe '.readable_schema_ids' do
    before do
      open_schema
      restricted_schema
    end

    it 'returns IDs matching readable_schemas' do
      ids = described_class.readable_schema_ids(member_user)
      expect(ids).to include(open_schema.id)
      expect(ids).not_to include(restricted_schema.id)
    end
  end
end
