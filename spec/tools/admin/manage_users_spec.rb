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
    it 'lists all users' do
      create(:user, name: 'bob')
      response = call_tool(described_class, user: admin, action: 'list')
      text = response_text(response)
      expect(text).to include('bob')
    end
  end

  describe 'delete action' do
    it 'deletes a user' do
      create(:user, name: 'to_delete')
      response = call_tool(described_class, user: admin,
                           action: 'delete', name: 'to_delete')
      expect(response_error?(response)).to be_falsey
      expect(SOT::User.first(name: 'to_delete')).to be_nil
    end

    it 'returns error for unknown user' do
      response = call_tool(described_class, user: admin,
                           action: 'delete', name: 'nonexistent')
      expect(response_error?(response)).to be true
    end

    it 'returns error when user has associated records' do
      worker = create(:user, name: 'worker')
      schema = create(:entity_schema)
      SOT::MutationService.create(schema: schema, data: { 'title' => 'item' }, user: worker)

      response = call_tool(described_class, user: admin,
                           action: 'delete', name: 'worker')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('Cannot delete')
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
