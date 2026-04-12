require 'spec_helper'

RSpec.describe SOT::Tools::Admin::ManageRoles, type: :tool do
  let(:admin) { create(:user, :admin) }

  describe 'create action' do
    it 'creates a role' do
      response = call_tool(described_class, user: admin,
                           action: 'create', name: 'support', description: 'Support team')
      expect(response_error?(response)).to be_falsey
      expect(response_text(response)).to include("Created role 'support'")
      expect(SOT::Role.first(name: 'support')).not_to be_nil
    end

    it 'returns error for duplicate name' do
      SOT::Role.create(name: 'support')
      response = call_tool(described_class, user: admin,
                           action: 'create', name: 'support')
      expect(response_error?(response)).to be true
    end

    it 'returns error for invalid name format' do
      response = call_tool(described_class, user: admin,
                           action: 'create', name: 'Invalid-Name')
      expect(response_error?(response)).to be true
    end

    it 'returns error without name' do
      response = call_tool(described_class, user: admin, action: 'create')
      expect(response_error?(response)).to be true
    end
  end

  describe 'list action' do
    it 'lists all roles with user counts' do
      response = call_tool(described_class, user: admin, action: 'list')
      text = response_text(response)
      expect(text).to include('admin')
      expect(text).to include('member')
      expect(text).to include('(system)')
    end
  end

  describe 'update action' do
    it 'updates a role description' do
      SOT::Role.create(name: 'support')
      response = call_tool(described_class, user: admin,
                           action: 'update', name: 'support', description: 'Updated desc')
      expect(response_error?(response)).to be_falsey
      expect(SOT::Role.first(name: 'support').description).to eq('Updated desc')
    end

    it 'returns error for unknown role' do
      response = call_tool(described_class, user: admin,
                           action: 'update', name: 'nonexistent')
      expect(response_error?(response)).to be true
    end
  end

  describe 'delete action' do
    it 'deletes a custom role' do
      SOT::Role.create(name: 'temp_role')
      response = call_tool(described_class, user: admin,
                           action: 'delete', name: 'temp_role')
      expect(response_error?(response)).to be_falsey
      expect(SOT::Role.first(name: 'temp_role')).to be_nil
    end

    it 'blocks deleting system role admin' do
      response = call_tool(described_class, user: admin,
                           action: 'delete', name: 'admin')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('system role')
    end

    it 'blocks deleting system role member' do
      response = call_tool(described_class, user: admin,
                           action: 'delete', name: 'member')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('system role')
    end

    it 'blocks deleting a role with assigned users' do
      role = SOT::Role.create(name: 'support')
      create(:user, role_id: role.id)
      response = call_tool(described_class, user: admin,
                           action: 'delete', name: 'support')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('still assigned')
    end

    it 'blocks deleting a role referenced in schema read_roles' do
      role = SOT::Role.create(name: 'reviewer')
      create(:table_schema, read_roles: JSON.generate(%w[member reviewer]))
      response = call_tool(described_class, user: admin,
                           action: 'delete', name: 'reviewer')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('schema ACLs')
    end

    it 'blocks deleting a role referenced only in create_roles' do
      role = SOT::Role.create(name: 'submitter')
      create(:table_schema, create_roles: JSON.generate(%w[member submitter]))
      response = call_tool(described_class, user: admin,
                           action: 'delete', name: 'submitter')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('schema ACLs')
    end

    it 'returns error for unknown role' do
      response = call_tool(described_class, user: admin,
                           action: 'delete', name: 'nonexistent')
      expect(response_error?(response)).to be true
    end
  end
end
