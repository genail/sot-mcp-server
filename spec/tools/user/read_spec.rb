require 'spec_helper'

RSpec.describe SOT::Tools::User::Read, type: :tool do
  let(:user) { create(:user) }
  let(:admin) { create(:user, :admin) }
  let(:schema) do
    create(:table_schema, namespace: 'docs', name: 'articles',
           fields: JSON.generate([
             { 'name' => 'title', 'type' => 'string', 'required' => true },
             { 'name' => 'content', 'type' => 'text' }
           ]))
  end
  let(:long_content) { 'A' * 100 + 'MIDDLE' + 'B' * 100 }
  let!(:record) do
    SOT::MutationService.create(
      schema: schema, user: user,
      data: { 'title' => 'Test Article', 'content' => long_content }
    )
  end

  describe 'read full field' do
    it 'returns the full field content' do
      response = call_tool(described_class, user: user,
                           record_id: record.id, field: 'content')
      text = response_text(response)
      expect(text).to include(long_content)
    end

    it 'returns the title field' do
      response = call_tool(described_class, user: user,
                           record_id: record.id, field: 'title')
      text = response_text(response)
      expect(text).to include('Test Article')
    end

    it 'includes field length information' do
      response = call_tool(described_class, user: user,
                           record_id: record.id, field: 'content')
      text = response_text(response)
      expect(text).to include(long_content.length.to_s)
    end
  end

  describe 'read with offset and limit' do
    it 'returns a slice of the field' do
      response = call_tool(described_class, user: user,
                           record_id: record.id, field: 'content',
                           offset: 95, limit: 20)
      text = response_text(response)
      expect(text).to include('AAAAAMIDDLEBB')
    end

    it 'returns from offset to end when no limit' do
      response = call_tool(described_class, user: user,
                           record_id: record.id, field: 'content',
                           offset: 100)
      text = response_text(response)
      expect(text).to include('MIDDLE')
      expect(text).to include('B' * 100)
    end

    it 'handles offset beyond field length' do
      response = call_tool(described_class, user: user,
                           record_id: record.id, field: 'content',
                           offset: 9999)
      text = response_text(response)
      expect(response_error?(response)).to be_falsey
      # Should return empty slice or indication of out-of-bounds
    end

    it 'includes offset and total length info' do
      response = call_tool(described_class, user: user,
                           record_id: record.id, field: 'content',
                           offset: 50, limit: 30)
      text = response_text(response)
      expect(text).to match(/offset/i)
    end
  end

  describe 'error cases' do
    it 'returns error for non-existent record' do
      response = call_tool(described_class, user: user,
                           record_id: 99999, field: 'content')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('not found')
    end

    it 'returns error for non-existent field' do
      response = call_tool(described_class, user: user,
                           record_id: record.id, field: 'nonexistent')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('nonexistent')
    end

    it 'requires record_id' do
      response = call_tool(described_class, user: user, field: 'content')
      expect(response_error?(response)).to be true
    end

    it 'requires field' do
      response = call_tool(described_class, user: user, record_id: record.id)
      expect(response_error?(response)).to be true
    end

    it 'returns error for negative offset' do
      response = call_tool(described_class, user: user,
                           record_id: record.id, field: 'content',
                           offset: -5)
      expect(response_error?(response)).to be true
    end

    it 'returns error for negative limit' do
      response = call_tool(described_class, user: user,
                           record_id: record.id, field: 'content',
                           limit: -1)
      expect(response_error?(response)).to be true
    end
  end

  describe 'RBAC enforcement' do
    let(:admin_only_schema) { create(:table_schema, :admin_only, namespace: 'secret', name: 'data') }
    let!(:secret_record) do
      SOT::MutationService.create(
        schema: admin_only_schema, user: admin,
        data: { 'title' => 'Secret Doc', 'count' => '42' }
      )
    end

    it 'returns not-found for admin-only record queried by member' do
      response = call_tool(described_class, user: user,
                           record_id: secret_record.id, field: 'title')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('not found')
    end

    it 'allows admin to read admin-only record field' do
      response = call_tool(described_class, user: admin,
                           record_id: secret_record.id, field: 'title')
      expect(response_error?(response)).to be_falsey
      expect(response_text(response)).to include('Secret Doc')
    end
  end
end
