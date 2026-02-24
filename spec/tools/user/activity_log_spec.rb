require 'spec_helper'

RSpec.describe SOT::Tools::User::ActivityLogTool, type: :tool do
  let(:user) { create(:user) }
  let(:schema) { create(:table_schema, :stateful, namespace: 'org', name: 'locks') }

  before do
    @record = SOT::MutationService.create(schema: schema, data: { 'title' => 'Test' }, state: 'open', user: user)
    SOT::MutationService.update(record: @record.reload, state: 'closed', expected_version: 1, user: user)
  end

  describe '.call' do
    it 'returns activity log entries with pagination header' do
      response = call_tool(described_class, user: user)
      text = response_text(response)
      expect(text).to include('create')
      expect(text).to include('update')
      expect(text).to include('Showing 1-2 of 2')
    end

    it 'filters by table' do
      other_schema = create(:table_schema, namespace: 'other', name: 'stuff')
      SOT::MutationService.create(schema: other_schema, data: { 'title' => 'Unrelated' }, user: user)

      response = call_tool(described_class, user: user, table: 'org.locks')
      text = response_text(response)
      expect(text).to include('Showing 1-2 of 2')
    end

    it 'filters by record_id' do
      response = call_tool(described_class, user: user, record_id: @record.id)
      text = response_text(response)
      expect(text).to include('Showing 1-2 of 2')
    end

    it 'filters by action' do
      response = call_tool(described_class, user: user, action: 'create')
      text = response_text(response)
      expect(text).to include('Showing 1-1 of 1')
    end

    it 'paginates with limit and offset' do
      response = call_tool(described_class, user: user, limit: 1, offset: 0)
      text = response_text(response)
      expect(text).to include('Showing 1-1 of 2')

      response2 = call_tool(described_class, user: user, limit: 1, offset: 1)
      text2 = response_text(response2)
      expect(text2).to include('Showing 2-2 of 2')
    end

    it 'returns error for unknown table' do
      response = call_tool(described_class, user: user, table: 'nonexistent')
      expect(response_error?(response)).to be true
    end

    it 'handles no entries' do
      DB.run('PRAGMA foreign_keys=OFF')
      SOT::ActivityLog.dataset.delete
      DB.run('PRAGMA foreign_keys=ON')
      response = call_tool(described_class, user: user)
      expect(response_text(response)).to include('No activity log entries found')
    end
  end
end
