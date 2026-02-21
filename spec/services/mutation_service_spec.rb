require 'spec_helper'

RSpec.describe SOT::MutationService do
  let(:user) { create(:user) }
  let(:user2) { create(:user) }
  let(:stateful_schema) { create(:entity_schema, :stateful) }
  let(:stateless_schema) { create(:entity_schema) }

  describe '.create' do
    it 'creates a record with valid data' do
      record = described_class.create(
        schema: stateless_schema,
        data: { 'title' => 'Test' },
        user: user
      )
      expect(record).to be_a(SOT::Record)
      expect(record.parsed_data['title']).to eq('Test')
      expect(record.created_by).to eq(user.id)
    end

    it 'sets default state for stateful schemas' do
      record = described_class.create(
        schema: stateful_schema,
        data: { 'title' => 'Test' },
        user: user
      )
      expect(record.state).to eq('open')
    end

    it 'allows explicit state for stateful schemas' do
      record = described_class.create(
        schema: stateful_schema,
        data: { 'title' => 'Test' },
        state: 'closed',
        user: user
      )
      expect(record.state).to eq('closed')
    end

    it 'sets nil state for stateless schemas' do
      record = described_class.create(
        schema: stateless_schema,
        data: { 'title' => 'Test' },
        user: user
      )
      expect(record.state).to be_nil
    end

    it 'raises when setting state on stateless schema' do
      expect {
        described_class.create(
          schema: stateless_schema,
          data: { 'title' => 'Test' },
          state: 'open',
          user: user
        )
      }.to raise_error(SOT::MutationService::ValidationError, /Cannot set state/)
    end

    it 'raises for missing required fields' do
      expect {
        described_class.create(
          schema: stateless_schema,
          data: { 'count' => '1' },
          user: user
        )
      }.to raise_error(SOT::MutationService::ValidationError, /Missing required fields.*title/)
    end

    it 'raises for unknown fields' do
      expect {
        described_class.create(
          schema: stateless_schema,
          data: { 'title' => 'Test', 'unknown_field' => 'x' },
          user: user
        )
      }.to raise_error(SOT::MutationService::ValidationError, /Unknown fields.*unknown_field/)
    end

    it 'raises for invalid state on stateful schema' do
      expect {
        described_class.create(
          schema: stateful_schema,
          data: { 'title' => 'Test' },
          state: 'nonexistent',
          user: user
        )
      }.to raise_error(SOT::MutationService::ValidationError, /Invalid state/)
    end

    it 'raises when data is not a Hash' do
      expect {
        described_class.create(
          schema: stateless_schema,
          data: 'not a hash',
          user: user
        )
      }.to raise_error(SOT::MutationService::ValidationError, /must be a Hash/)
    end

    it 'creates an activity log entry' do
      record = described_class.create(
        schema: stateless_schema,
        data: { 'title' => 'Test' },
        user: user
      )
      logs = SOT::ActivityLog.where(record_id: record.id).all
      expect(logs.length).to eq(1)
      expect(logs.first.action).to eq('create')
      expect(logs.first.user_id).to eq(user.id)
      changes = logs.first.parsed_changes
      expect(changes['before']).to be_nil
      expect(changes['after']['data']['title']).to eq('Test')
    end
  end

  describe '.update' do
    let(:record) do
      described_class.create(
        schema: stateful_schema,
        data: { 'title' => 'Original' },
        state: 'open',
        user: user
      )
    end

    it 'updates data' do
      result = described_class.update(
        record: record,
        data: { 'title' => 'Updated' },
        user: user2
      )
      expect(result.parsed_data['title']).to eq('Updated')
      expect(result.updated_by).to eq(user2.id)
    end

    it 'updates state' do
      result = described_class.update(
        record: record,
        state: 'closed',
        user: user
      )
      expect(result.state).to eq('closed')
    end

    it 'succeeds when preconditions match' do
      result = described_class.update(
        record: record,
        state: 'closed',
        preconditions: { 'state' => 'open' },
        user: user
      )
      expect(result.state).to eq('closed')
    end

    it 'raises PreconditionFailed when state precondition fails' do
      expect {
        described_class.update(
          record: record,
          state: 'closed',
          preconditions: { 'state' => 'closed' },
          user: user
        )
      }.to raise_error(SOT::MutationService::PreconditionFailed) do |e|
        expect(e.expected[:state]).to eq('closed')
        expect(e.actual[:state]).to eq('open')
      end
    end

    it 'raises PreconditionFailed when data field precondition fails' do
      expect {
        described_class.update(
          record: record,
          data: { 'title' => 'New' },
          preconditions: { 'title' => 'Wrong' },
          user: user
        )
      }.to raise_error(SOT::MutationService::PreconditionFailed)
    end

    it 'succeeds when data field precondition matches' do
      result = described_class.update(
        record: record,
        data: { 'title' => 'New' },
        preconditions: { 'title' => 'Original' },
        user: user
      )
      expect(result.parsed_data['title']).to eq('New')
    end

    it 'distinguishes nil from empty string in data preconditions' do
      record_with_nil = described_class.create(
        schema: stateful_schema,
        data: { 'title' => 'Test' },
        user: user
      )
      # 'count' field is not set → nil. Precondition expecting "" should fail.
      expect {
        described_class.update(
          record: record_with_nil,
          data: { 'title' => 'Updated' },
          preconditions: { 'count' => '' },
          user: user
        )
      }.to raise_error(SOT::MutationService::PreconditionFailed)
    end

    it 'raises when setting state on stateless entity via update' do
      stateless_record = described_class.create(
        schema: stateless_schema,
        data: { 'title' => 'Test' },
        user: user
      )
      expect {
        described_class.update(
          record: stateless_record,
          state: 'anything',
          user: user
        )
      }.to raise_error(SOT::MutationService::ValidationError, /Cannot set state/)
    end

    it 'raises for invalid state' do
      expect {
        described_class.update(
          record: record,
          state: 'nonexistent',
          user: user
        )
      }.to raise_error(SOT::MutationService::ValidationError, /Invalid state/)
    end

    it 'creates an activity log entry with before/after diff' do
      described_class.update(
        record: record,
        data: { 'title' => 'Updated' },
        state: 'closed',
        user: user2
      )
      logs = SOT::ActivityLog.where(record_id: record.id, action: 'update').all
      expect(logs.length).to eq(1)
      changes = logs.first.parsed_changes
      expect(changes['before']['data']['title']).to eq('Original')
      expect(changes['before']['state']).to eq('open')
      expect(changes['after']['data']['title']).to eq('Updated')
      expect(changes['after']['state']).to eq('closed')
    end
  end

  describe '.delete' do
    let(:record) do
      described_class.create(
        schema: stateful_schema,
        data: { 'title' => 'ToDelete' },
        state: 'open',
        user: user
      )
    end

    it 'deletes the record' do
      id = record.id
      described_class.delete(record: record, user: user)
      expect(SOT::Record[id]).to be_nil
    end

    it 'succeeds when preconditions match' do
      expect {
        described_class.delete(
          record: record,
          preconditions: { 'state' => 'open' },
          user: user
        )
      }.not_to raise_error
    end

    it 'raises PreconditionFailed when preconditions fail' do
      expect {
        described_class.delete(
          record: record,
          preconditions: { 'state' => 'closed' },
          user: user
        )
      }.to raise_error(SOT::MutationService::PreconditionFailed)
    end

    it 'creates an activity log entry' do
      id = record.id
      described_class.delete(record: record, user: user)
      logs = SOT::ActivityLog.where(schema_id: stateful_schema.id, action: 'delete').all
      expect(logs.length).to eq(1)
      changes = logs.first.parsed_changes
      expect(changes['before']['data']['title']).to eq('ToDelete')
      expect(changes['after']).to be_nil
    end
  end

  describe 'activity log accuracy across multiple operations' do
    it 'tracks the full lifecycle' do
      record = described_class.create(
        schema: stateful_schema,
        data: { 'title' => 'v1' },
        user: user
      )
      described_class.update(record: record.reload, data: { 'title' => 'v2' }, user: user)
      described_class.update(record: record.reload, data: { 'title' => 'v3' }, user: user)
      described_class.delete(record: record.reload, user: user)

      logs = SOT::ActivityLog.where(schema_id: stateful_schema.id).order(:id).all
      expect(logs.length).to eq(4)

      expect(logs[0].action).to eq('create')
      expect(logs[0].parsed_changes['before']).to be_nil
      expect(logs[0].parsed_changes['after']['data']['title']).to eq('v1')

      expect(logs[1].action).to eq('update')
      expect(logs[1].parsed_changes['before']['data']['title']).to eq('v1')
      expect(logs[1].parsed_changes['after']['data']['title']).to eq('v2')

      expect(logs[2].action).to eq('update')
      expect(logs[2].parsed_changes['before']['data']['title']).to eq('v2')
      expect(logs[2].parsed_changes['after']['data']['title']).to eq('v3')

      expect(logs[3].action).to eq('delete')
      expect(logs[3].parsed_changes['before']['data']['title']).to eq('v3')
      expect(logs[3].parsed_changes['after']).to be_nil
    end
  end
end
