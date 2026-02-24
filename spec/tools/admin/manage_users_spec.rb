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
                action: 'create', name: 'new_admin', is_admin: true)
      expect(SOT::User.first(name: 'new_admin').is_admin).to be true
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
end
