require 'spec_helper'

RSpec.describe SOT::Tools::User::ActivityLogTool, type: :tool do
  let(:user) { create(:user) }
  let(:schema) { create(:entity_schema, :stateful, namespace: 'org', name: 'locks') }

  before do
    @record = SOT::MutationService.create(schema: schema, data: { 'title' => 'Test' }, state: 'open', user: user)
    SOT::MutationService.update(record: @record.reload, state: 'closed', user: user)
  end

  describe '.call' do
    it 'returns activity log entries' do
      response = call_tool(described_class, user: user)
      text = response_text(response)
      expect(text).to include('create')
      expect(text).to include('update')
      expect(text).to include('Activity log (2 entries)')
    end

    it 'filters by entity' do
      other_schema = create(:entity_schema, namespace: 'other', name: 'stuff')
      SOT::MutationService.create(schema: other_schema, data: { 'title' => 'Unrelated' }, user: user)

      response = call_tool(described_class, user: user, entity: 'org.locks')
      text = response_text(response)
      expect(text).to include('2 entries')
    end

    it 'filters by record_id' do
      response = call_tool(described_class, user: user, record_id: @record.id)
      text = response_text(response)
      expect(text).to include('2 entries')
    end

    it 'filters by action' do
      response = call_tool(described_class, user: user, action: 'create')
      text = response_text(response)
      expect(text).to include('1 entries')
    end

    it 'returns error for unknown entity' do
      response = call_tool(described_class, user: user, entity: 'nonexistent')
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
