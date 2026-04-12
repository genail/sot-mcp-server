require 'spec_helper'

RSpec.describe 'RBAC enforcement', type: :tool do
  let(:member_user) { create(:user) }
  let(:admin_user) { create(:user, :admin) }
  let(:admin_only_schema) { create(:table_schema, :admin_only, namespace: 'secret', name: 'data') }
  let(:readable_schema) { create(:table_schema) }

  describe 'sot_query' do
    it 'returns not-found for admin-only table queried by member' do
      admin_only_schema
      response = call_tool(SOT::Tools::User::Query, user: member_user,
                           table: 'secret.data')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('not found')
    end

    it 'allows admin to query admin-only table' do
      admin_only_schema
      response = call_tool(SOT::Tools::User::Query, user: admin_user,
                           table: 'secret.data')
      expect(response_error?(response)).to be_falsey
    end

    it 'returns not-found for record_id in admin-only schema' do
      record = SOT::MutationService.create(
        schema: admin_only_schema, data: { 'title' => 'Secret' }, user: admin_user
      )
      response = call_tool(SOT::Tools::User::Query, user: member_user,
                           table: readable_schema.full_name, record_id: record.id)
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('not found')
    end
  end

  describe 'sot_mutate' do
    it 'returns not-found when member tries to create in admin-only table' do
      admin_only_schema
      response = call_tool(SOT::Tools::User::Mutate, user: member_user,
                           action: 'create', table: 'secret.data',
                           data: { 'title' => 'test' })
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('not found')
    end

    it 'returns not-found when member tries to update in admin-only table' do
      record = SOT::MutationService.create(
        schema: admin_only_schema, data: { 'title' => 'Secret' }, user: admin_user
      )
      response = call_tool(SOT::Tools::User::Mutate, user: member_user,
                           action: 'update', record_id: record.id,
                           data: { 'title' => 'Hacked' }, version: 1)
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('not found')
    end

    it 'returns not-found when member tries to delete in admin-only table' do
      record = SOT::MutationService.create(
        schema: admin_only_schema, data: { 'title' => 'Secret' }, user: admin_user
      )
      response = call_tool(SOT::Tools::User::Mutate, user: member_user,
                           action: 'delete', record_id: record.id, version: 1)
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('not found')
    end
  end

  describe 'sot_describe_tables' do
    it 'excludes admin-only tables for member' do
      admin_only_schema
      readable_schema
      response = call_tool(SOT::Tools::User::DescribeTables, user: member_user)
      text = response_text(response)
      expect(text).to include(readable_schema.full_name)
      expect(text).not_to include('secret.data')
    end

    it 'shows admin-only tables for admin' do
      admin_only_schema
      response = call_tool(SOT::Tools::User::DescribeTables, user: admin_user)
      expect(response_text(response)).to include('secret.data')
    end
  end

  describe 'granular CRUD permissions' do
    let(:read_only_schema) { create(:table_schema, :read_only_member, namespace: 'docs', name: 'guides') }

    it 'allows member to read a read-only table' do
      SOT::MutationService.create(
        schema: read_only_schema, data: { 'title' => 'Guide' }, user: admin_user
      )
      response = call_tool(SOT::Tools::User::Query, user: member_user,
                           table: 'docs.guides')
      expect(response_error?(response)).to be_falsey
      expect(response_text(response)).to include('Guide')
    end

    it 'blocks member from creating in read-only table' do
      read_only_schema
      response = call_tool(SOT::Tools::User::Mutate, user: member_user,
                           action: 'create', table: 'docs.guides',
                           data: { 'title' => 'New' })
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('not found')
    end

    it 'blocks member from updating in read-only table' do
      record = SOT::MutationService.create(
        schema: read_only_schema, data: { 'title' => 'Guide' }, user: admin_user
      )
      response = call_tool(SOT::Tools::User::Mutate, user: member_user,
                           action: 'update', record_id: record.id,
                           data: { 'title' => 'Changed' }, version: 1)
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('not found')
    end

    it 'blocks member from deleting in read-only table' do
      record = SOT::MutationService.create(
        schema: read_only_schema, data: { 'title' => 'Guide' }, user: admin_user
      )
      response = call_tool(SOT::Tools::User::Mutate, user: member_user,
                           action: 'delete', record_id: record.id, version: 1)
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('not found')
    end

    it 'shows read-only table in describe_tables for member' do
      read_only_schema
      response = call_tool(SOT::Tools::User::DescribeTables, user: member_user)
      expect(response_text(response)).to include('docs.guides')
    end
  end

  describe 'multi-table mixed permissions' do
    it 'returns not-found when any table is inaccessible' do
      readable_schema
      admin_only_schema
      response = call_tool(SOT::Tools::User::Query, user: member_user,
                           table: [readable_schema.full_name, 'secret.data'])
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('not found')
    end
  end

  describe 'sot_activity_log' do
    it 'excludes activity for admin-only schemas from member view' do
      SOT::MutationService.create(
        schema: admin_only_schema, data: { 'title' => 'Secret' }, user: admin_user
      )
      response = call_tool(SOT::Tools::User::ActivityLogTool, user: member_user)
      text = response_text(response)
      expect(text).not_to include('secret.data')
    end

    it 'returns not-found when member filters by admin-only table' do
      admin_only_schema
      response = call_tool(SOT::Tools::User::ActivityLogTool, user: member_user,
                           table: 'secret.data')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('not found')
    end
  end
end

RSpec.describe 'RBAC enforcement (REST API)', type: :api do
  let(:admin_pair) { SOT::User.create_with_token(name: 'rbac_admin', role_name: 'admin') }
  let(:admin_token) { admin_pair.last }
  let(:user_pair) { SOT::User.create_with_token(name: 'rbac_user') }
  let(:user_token) { user_pair.last }

  let!(:admin_only_schema) { create(:table_schema, :admin_only, namespace: 'secret', name: 'items') }

  describe 'GET /api/schemas' do
    it 'excludes admin-only schemas for member' do
      get '/api/schemas', {}, auth_header(user_token)
      expect(last_response.status).to eq(200)
      names = json_body['schemas'].map { |s| s['full_name'] }
      expect(names).not_to include('secret.items')
    end
  end

  describe 'GET /api/records/:table' do
    it 'returns 404 for admin-only table queried by member' do
      get '/api/records/secret.items', {}, auth_header(user_token)
      expect(last_response.status).to eq(404)
    end
  end

  describe 'GET /api/activity_log' do
    it 'returns 404 when member filters by admin-only table' do
      get '/api/activity_log', { table: 'secret.items' }, auth_header(user_token)
      expect(last_response.status).to eq(404)
    end
  end

  describe 'POST /api/records' do
    it 'returns 404 when member creates in admin-only table' do
      post_json '/api/records', {
        table: 'secret.items',
        data: { 'title' => 'test' }
      }, auth_header(user_token)
      expect(last_response.status).to eq(404)
    end
  end

  describe 'PATCH /api/records/:id' do
    it 'returns 404 when member updates record in admin-only table' do
      admin = admin_pair.first
      record = SOT::MutationService.create(
        schema: admin_only_schema, data: { 'title' => 'Secret' }, user: admin
      )
      patch_json "/api/records/#{record.id}", {
        data: { 'title' => 'Hacked' }, version: 1
      }, auth_header(user_token)
      expect(last_response.status).to eq(404)
    end
  end

  describe 'DELETE /api/records/:id' do
    it 'returns 404 when member deletes record in admin-only table' do
      admin = admin_pair.first
      record = SOT::MutationService.create(
        schema: admin_only_schema, data: { 'title' => 'Secret' }, user: admin
      )
      delete_json "/api/records/#{record.id}", { version: 1 }, auth_header(user_token)
      expect(last_response.status).to eq(404)
    end
  end
end
