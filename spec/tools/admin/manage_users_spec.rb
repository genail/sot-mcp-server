require 'spec_helper'

RSpec.describe SOT::Tools::Admin::ManageUsers, type: :tool do
  let(:admin) { create(:user, :admin) }

  describe 'create action' do
    it 'creates a user and returns token' do
      response = call_tool(described_class, user: admin,
                           action: 'create', name: 'alice')
      expect(response_error?(response)).to be_falsey
      text = response_text(response)
      expect(text).to include("Created user 'alice'")
      expect(text).to include('Token')
      expect(SOT::User.where(name: 'alice').count).to eq(1)
    end

    it 'can create admin users' do
      call_tool(described_class, user: admin,
                action: 'create', name: 'new_admin', role: 'admin')
      expect(SOT::User.first(name: 'new_admin').admin?).to be true
    end

    it 'returns error without name' do
      response = call_tool(described_class, user: admin,
                           action: 'create')
      expect(response_error?(response)).to be true
    end
  end

  describe 'list action' do
    it 'lists all users with status' do
      create(:user, name: 'bob')
      create(:user, :inactive, name: 'charlie')
      response = call_tool(described_class, user: admin, action: 'list')
      text = response_text(response)
      expect(text).to include('bob')
      expect(text).to include('status: active')
      expect(text).to include('charlie')
      expect(text).to include('status: inactive')
    end
  end

  describe 'deactivate action' do
    it 'deactivates a user' do
      create(:user, name: 'to_deactivate')
      response = call_tool(described_class, user: admin,
                           action: 'deactivate', name: 'to_deactivate')
      expect(response_error?(response)).to be_falsey
      expect(response_text(response)).to include('Deactivated')
      expect(SOT::User.first(name: 'to_deactivate').is_active).to be false
    end

    it 'returns error for unknown user' do
      response = call_tool(described_class, user: admin,
                           action: 'deactivate', name: 'nonexistent')
      expect(response_error?(response)).to be true
    end

    it 'returns error when user is already inactive' do
      create(:user, :inactive, name: 'already_inactive')
      response = call_tool(described_class, user: admin,
                           action: 'deactivate', name: 'already_inactive')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('already inactive')
    end
  end

  describe 'activate action' do
    it 'reactivates a user' do
      create(:user, :inactive, name: 'to_activate')
      response = call_tool(described_class, user: admin,
                           action: 'activate', name: 'to_activate')
      expect(response_error?(response)).to be_falsey
      expect(response_text(response)).to include('Reactivated')
      expect(SOT::User.first(name: 'to_activate').is_active).to be true
    end

    it 'returns error for unknown user' do
      response = call_tool(described_class, user: admin,
                           action: 'activate', name: 'nonexistent')
      expect(response_error?(response)).to be true
    end

    it 'returns error when user is already active' do
      create(:user, name: 'already_active')
      response = call_tool(described_class, user: admin,
                           action: 'activate', name: 'already_active')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('already active')
    end
  end

  describe 'regenerate_token action' do
    it 'regenerates token and returns it' do
      create(:user, name: 'alice')
      response = call_tool(described_class, user: admin,
                           action: 'regenerate_token', name: 'alice')
      text = response_text(response)
      expect(text).to include('Regenerated token')
      expect(text).to include('New token')
    end
  end

  describe 'rename action' do
    it 'renames a user' do
      create(:user, name: 'alice')
      response = call_tool(described_class, user: admin,
                           action: 'rename', name: 'alice', new_name: 'alice_new')
      expect(response_error?(response)).to be_falsey
      expect(response_text(response)).to include("Renamed user 'alice' to 'alice_new'")
      expect(SOT::User.first(name: 'alice_new')).not_to be_nil
      expect(SOT::User.first(name: 'alice')).to be_nil
    end

    it 'cascades rename to user-type fields' do
      alice = create(:user, name: 'alice')
      schema = create(:table_schema, fields: JSON.generate([
        { 'name' => 'title', 'type' => 'string', 'required' => true },
        { 'name' => 'assignee', 'type' => 'user', 'required' => false }
      ]))
      record = SOT::MutationService.create(
        schema: schema,
        data: { 'title' => 'Task', 'assignee' => 'alice' },
        user: admin
      )

      call_tool(described_class, user: admin,
                action: 'rename', name: 'alice', new_name: 'alice_renamed')

      expect(record.reload.parsed_data['assignee']).to eq('alice_renamed')
    end

    it 'attributes cascade activity log entries to the admin user' do
      alice = create(:user, name: 'alice')
      schema = create(:table_schema, fields: JSON.generate([
        { 'name' => 'title', 'type' => 'string', 'required' => true },
        { 'name' => 'assignee', 'type' => 'user', 'required' => false }
      ]))
      record = SOT::MutationService.create(
        schema: schema,
        data: { 'title' => 'Task', 'assignee' => 'alice' },
        user: admin
      )

      call_tool(described_class, user: admin,
                action: 'rename', name: 'alice', new_name: 'alice_renamed')

      cascade_log = SOT::ActivityLog.where(record_id: record.id, action: 'update').order(:id).last
      expect(cascade_log.user_id).to eq(admin.id)
    end

    it 'returns error without name' do
      response = call_tool(described_class, user: admin,
                           action: 'rename', new_name: 'new')
      expect(response_error?(response)).to be true
    end

    it 'returns error without new_name' do
      create(:user, name: 'alice')
      response = call_tool(described_class, user: admin,
                           action: 'rename', name: 'alice')
      expect(response_error?(response)).to be true
    end

    it 'returns error for unknown user' do
      response = call_tool(described_class, user: admin,
                           action: 'rename', name: 'nonexistent', new_name: 'new')
      expect(response_error?(response)).to be true
    end
  end

  describe 'set_role action' do
    it 'changes a user role' do
      user = create(:user, name: 'alice')
      SOT::Role.create(name: 'support')
      response = call_tool(described_class, user: admin,
                           action: 'set_role', name: 'alice', role: 'support')
      expect(response_error?(response)).to be_falsey
      expect(response_text(response)).to include("Set role of user 'alice' to 'support'")
      expect(user.reload.role.name).to eq('support')
    end

    it 'blocks demoting the last active admin' do
      response = call_tool(described_class, user: admin,
                           action: 'set_role', name: admin.name, role: 'member')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('last active admin')
    end

    it 'allows demotion when multiple admins exist' do
      other_admin = create(:user, :admin, name: 'other_admin')
      response = call_tool(described_class, user: admin,
                           action: 'set_role', name: other_admin.name, role: 'member')
      expect(response_error?(response)).to be_falsey
      expect(other_admin.reload.role.name).to eq('member')
    end

    it 'does not count inactive admins toward admin count' do
      create(:user, :admin, :inactive, name: 'inactive_admin')
      response = call_tool(described_class, user: admin,
                           action: 'set_role', name: admin.name, role: 'member')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('last active admin')
    end

    it 'returns error for unknown user' do
      response = call_tool(described_class, user: admin,
                           action: 'set_role', name: 'nonexistent', role: 'member')
      expect(response_error?(response)).to be true
    end

    it 'returns error for unknown role' do
      create(:user, name: 'alice')
      response = call_tool(described_class, user: admin,
                           action: 'set_role', name: 'alice', role: 'nonexistent')
      expect(response_error?(response)).to be true
    end

    it 'returns error without name' do
      response = call_tool(described_class, user: admin,
                           action: 'set_role', role: 'member')
      expect(response_error?(response)).to be true
    end

    it 'returns error without role' do
      create(:user, name: 'alice')
      response = call_tool(described_class, user: admin,
                           action: 'set_role', name: 'alice')
      expect(response_error?(response)).to be true
    end
  end

  describe 'create action with roles' do
    it 'defaults to member role when no role specified' do
      response = call_tool(described_class, user: admin,
                           action: 'create', name: 'default_user')
      expect(response_error?(response)).to be_falsey
      expect(SOT::User.first(name: 'default_user').role.name).to eq('member')
    end

    it 'returns error for invalid role name' do
      response = call_tool(described_class, user: admin,
                           action: 'create', name: 'alice', role: 'nonexistent')
      expect(response_error?(response)).to be true
    end
  end
end
