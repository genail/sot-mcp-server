require 'spec_helper'

RSpec.describe SOT::MutationService do
  let(:user) { create(:user) }
  let(:user2) { create(:user) }
  let(:stateful_schema) { create(:table_schema, :stateful) }
  let(:stateless_schema) { create(:table_schema) }

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

    it 'handles symbol-keyed data from MCP gem without duplicate JSON keys' do
      record = described_class.create(
        schema: stateless_schema,
        data: { title: 'Test' },
        user: user
      )
      expect(record.parsed_data['title']).to eq('Test')
      expect(record.data.scan('"title"').length).to eq(1)
    end

    it 'sets version to 1' do
      record = described_class.create(
        schema: stateless_schema,
        data: { 'title' => 'Test' },
        user: user
      )
      expect(record.current_version).to eq(1)
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

    it 'merges data by default (preserves unmentioned fields)' do
      result = described_class.update(
        record: record,
        data: { 'title' => 'Updated' },
        expected_version: 1,
        user: user2
      )
      expect(result.parsed_data['title']).to eq('Updated')
      expect(result.updated_by).to eq(user2.id)
    end

    it 'does not produce duplicate JSON keys when data has symbol keys (MCP gem sends symbols)' do
      result = described_class.update(
        record: record,
        data: { title: 'Updated Title' },
        expected_version: 1,
        user: user
      )
      raw_json = result.data
      occurrences = raw_json.scan('"title"').length
      expect(occurrences).to eq(1), "Expected 'title' to appear once in raw JSON but found #{occurrences} times: #{raw_json}"
    end

    it 'increments version on update' do
      result = described_class.update(
        record: record,
        data: { 'title' => 'Updated' },
        expected_version: 1,
        user: user
      )
      expect(result.current_version).to eq(2)
    end

    it 'increments version on append-only update' do
      text_schema = create(:table_schema, fields: JSON.generate([
        { 'name' => 'title', 'type' => 'string', 'required' => true },
        { 'name' => 'log', 'type' => 'text', 'required' => false }
      ]))
      rec = described_class.create(schema: text_schema, data: { 'title' => 'Task', 'log' => 'Line 1' }, user: user)
      result = described_class.update(
        record: rec,
        append_data: { 'log' => "\nLine 2" },
        user: user
      )
      expect(result.current_version).to eq(2)
    end

    it 'raises VersionConflict when version does not match' do
      expect {
        described_class.update(
          record: record,
          data: { 'title' => 'Updated' },
          expected_version: 99,
          user: user
        )
      }.to raise_error(SOT::MutationService::VersionConflict) do |e|
        expect(e.expected_version).to eq(99)
        expect(e.actual_version).to eq(1)
      end
    end

    it 'raises ValidationError when version is missing for non-append update' do
      expect {
        described_class.update(
          record: record,
          data: { 'title' => 'Updated' },
          user: user
        )
      }.to raise_error(SOT::MutationService::ValidationError, /version is required/)
    end

    it 'does not require version for append-only update' do
      text_schema = create(:table_schema, fields: JSON.generate([
        { 'name' => 'title', 'type' => 'string', 'required' => true },
        { 'name' => 'log', 'type' => 'text', 'required' => false }
      ]))
      rec = described_class.create(schema: text_schema, data: { 'title' => 'Task', 'log' => 'Line 1' }, user: user)
      expect {
        described_class.update(
          record: rec,
          append_data: { 'log' => "\nLine 2" },
          user: user
        )
      }.not_to raise_error
    end

    it 'requires version when append_data is combined with data' do
      text_schema = create(:table_schema, fields: JSON.generate([
        { 'name' => 'title', 'type' => 'string', 'required' => true },
        { 'name' => 'log', 'type' => 'text', 'required' => false }
      ]))
      rec = described_class.create(schema: text_schema, data: { 'title' => 'Task', 'log' => 'Line 1' }, user: user)
      expect {
        described_class.update(
          record: rec,
          data: { 'title' => 'New' },
          append_data: { 'log' => "\nLine 2" },
          user: user
        )
      }.to raise_error(SOT::MutationService::ValidationError, /version is required/)
    end

    it 'removes fields set to null during merge' do
      record_with_count = described_class.create(
        schema: stateful_schema,
        data: { 'title' => 'Test', 'count' => '5' },
        user: user
      )
      result = described_class.update(
        record: record_with_count,
        data: { 'count' => nil },
        expected_version: 1,
        user: user
      )
      expect(result.parsed_data).to eq({ 'title' => 'Test' })
    end

    it 'replaces data entirely when replace_data is true' do
      result = described_class.update(
        record: record,
        data: { 'title' => 'Replaced' },
        replace_data: true,
        expected_version: 1,
        user: user2
      )
      expect(result.parsed_data).to eq({ 'title' => 'Replaced' })
    end

    it 'updates state' do
      result = described_class.update(
        record: record,
        state: 'closed',
        expected_version: 1,
        user: user
      )
      expect(result.state).to eq('closed')
    end

    it 'succeeds when preconditions match' do
      result = described_class.update(
        record: record,
        state: 'closed',
        preconditions: { 'state' => 'open' },
        expected_version: 1,
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
          expected_version: 1,
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
          expected_version: 1,
          user: user
        )
      }.to raise_error(SOT::MutationService::PreconditionFailed)
    end

    it 'succeeds when data field precondition matches' do
      result = described_class.update(
        record: record,
        data: { 'title' => 'New' },
        preconditions: { 'title' => 'Original' },
        expected_version: 1,
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
      expect {
        described_class.update(
          record: record_with_nil,
          data: { 'title' => 'Updated' },
          preconditions: { 'count' => '' },
          expected_version: 1,
          user: user
        )
      }.to raise_error(SOT::MutationService::PreconditionFailed)
    end

    it 'raises when setting state on stateless table via update' do
      stateless_record = described_class.create(
        schema: stateless_schema,
        data: { 'title' => 'Test' },
        user: user
      )
      expect {
        described_class.update(
          record: stateless_record,
          state: 'anything',
          expected_version: 1,
          user: user
        )
      }.to raise_error(SOT::MutationService::ValidationError, /Cannot set state/)
    end

    it 'raises for invalid state' do
      expect {
        described_class.update(
          record: record,
          state: 'nonexistent',
          expected_version: 1,
          user: user
        )
      }.to raise_error(SOT::MutationService::ValidationError, /Invalid state/)
    end

    context 'with append_data' do
      let(:text_schema) do
        create(:table_schema, fields: JSON.generate([
          { 'name' => 'title', 'type' => 'string', 'required' => true },
          { 'name' => 'log', 'type' => 'text', 'required' => false },
          { 'name' => 'count', 'type' => 'integer', 'required' => false }
        ]))
      end

      let(:text_record) do
        described_class.create(
          schema: text_schema,
          data: { 'title' => 'Task', 'log' => 'Line 1' },
          user: user
        )
      end

      it 'appends to an existing field value' do
        result = described_class.update(
          record: text_record,
          append_data: { 'log' => "\nLine 2" },
          user: user
        )
        expect(result.parsed_data['log']).to eq("Line 1\nLine 2")
      end

      it 'sets value when field is empty/nil' do
        empty_record = described_class.create(
          schema: text_schema,
          data: { 'title' => 'Task' },
          user: user
        )
        result = described_class.update(
          record: empty_record,
          append_data: { 'log' => 'First entry' },
          user: user
        )
        expect(result.parsed_data['log']).to eq('First entry')
      end

      it 'works together with data (different fields)' do
        result = described_class.update(
          record: text_record,
          data: { 'title' => 'Updated Task' },
          append_data: { 'log' => "\nLine 2" },
          expected_version: 1,
          user: user
        )
        expect(result.parsed_data['title']).to eq('Updated Task')
        expect(result.parsed_data['log']).to eq("Line 1\nLine 2")
      end

      it 'raises when same field appears in both data and append_data' do
        expect {
          described_class.update(
            record: text_record,
            data: { 'log' => 'replaced' },
            append_data: { 'log' => ' appended' },
            expected_version: 1,
            user: user
          )
        }.to raise_error(SOT::MutationService::ValidationError, /both data and append_data/)
      end

      it 'raises for non-appendable field types' do
        expect {
          described_class.update(
            record: text_record,
            append_data: { 'count' => '1' },
            user: user
          )
        }.to raise_error(SOT::MutationService::ValidationError, /Cannot append.*count.*integer/)
      end

      it 'raises for unknown fields in append_data' do
        expect {
          described_class.update(
            record: text_record,
            append_data: { 'nonexistent' => 'value' },
            user: user
          )
        }.to raise_error(SOT::MutationService::ValidationError, /Unknown field/)
      end

      it 'raises when append_data is not a Hash' do
        expect {
          described_class.update(
            record: text_record,
            append_data: 'not a hash',
            user: user
          )
        }.to raise_error(SOT::MutationService::ValidationError, /must be a Hash/)
      end

      it 'records correct before/after in activity log' do
        described_class.update(
          record: text_record,
          append_data: { 'log' => "\nLine 2" },
          user: user
        )
        logs = SOT::ActivityLog.where(record_id: text_record.id, action: 'update').all
        changes = logs.last.parsed_changes
        expect(changes['before']['data']['log']).to eq('Line 1')
        expect(changes['after']['data']['log']).to eq("Line 1\nLine 2")
      end
    end

    context 'with edit_data' do
      let(:text_schema) do
        create(:table_schema, fields: JSON.generate([
          { 'name' => 'title', 'type' => 'string', 'required' => true },
          { 'name' => 'content', 'type' => 'text', 'required' => false },
          { 'name' => 'count', 'type' => 'integer', 'required' => false }
        ]))
      end

      let(:text_record) do
        described_class.create(
          schema: text_schema,
          data: { 'title' => 'Doc', 'content' => 'The quick brown fox jumps over the lazy dog.' },
          user: user
        )
      end

      it 'replaces text within a field' do
        result = described_class.update(
          record: text_record,
          edit_data: { 'content' => [{ 'search' => 'brown fox', 'replace' => 'red cat' }] },
          expected_version: 1,
          user: user
        )
        expect(result.parsed_data['content']).to eq('The quick red cat jumps over the lazy dog.')
      end

      it 'supports multiple non-overlapping edits on the same field' do
        result = described_class.update(
          record: text_record,
          edit_data: { 'content' => [
            { 'search' => 'quick', 'replace' => 'slow' },
            { 'search' => 'lazy', 'replace' => 'energetic' }
          ] },
          expected_version: 1,
          user: user
        )
        expect(result.parsed_data['content']).to eq('The slow brown fox jumps over the energetic dog.')
      end

      it 'supports deletion via empty replace string' do
        result = described_class.update(
          record: text_record,
          edit_data: { 'content' => [{ 'search' => 'brown ', 'replace' => '' }] },
          expected_version: 1,
          user: user
        )
        expect(result.parsed_data['content']).to eq('The quick fox jumps over the lazy dog.')
      end

      it 'requires version' do
        expect {
          described_class.update(
            record: text_record,
            edit_data: { 'content' => [{ 'search' => 'fox', 'replace' => 'cat' }] },
            user: user
          )
        }.to raise_error(SOT::MutationService::ValidationError, /version is required/)
      end

      it 'raises when search text is not found' do
        expect {
          described_class.update(
            record: text_record,
            edit_data: { 'content' => [{ 'search' => 'nonexistent text', 'replace' => 'x' }] },
            expected_version: 1,
            user: user
          )
        }.to raise_error(SOT::MutationService::ValidationError, /search text not found/)
      end

      it 'raises when search text matches multiple locations' do
        rec = described_class.create(
          schema: text_schema,
          data: { 'title' => 'Doc', 'content' => 'the cat and the dog' },
          user: user
        )
        expect {
          described_class.update(
            record: rec,
            edit_data: { 'content' => [{ 'search' => 'the', 'replace' => 'a' }] },
            expected_version: 1,
            user: user
          )
        }.to raise_error(SOT::MutationService::ValidationError, /matches 2 locations/)
      end

      it 'raises when edit regions overlap' do
        rec = described_class.create(
          schema: text_schema,
          data: { 'title' => 'Doc', 'content' => 'abcdef' },
          user: user
        )
        expect {
          described_class.update(
            record: rec,
            edit_data: { 'content' => [
              { 'search' => 'bcde', 'replace' => 'X' },
              { 'search' => 'cdef', 'replace' => 'Y' }
            ] },
            expected_version: 1,
            user: user
          )
        }.to raise_error(SOT::MutationService::ValidationError, /overlap/)
      end

      it 'raises for non-editable field types' do
        expect {
          described_class.update(
            record: text_record,
            edit_data: { 'count' => [{ 'search' => '1', 'replace' => '2' }] },
            expected_version: 1,
            user: user
          )
        }.to raise_error(SOT::MutationService::ValidationError, /Cannot edit.*count.*integer/)
      end

      it 'raises for unknown fields' do
        expect {
          described_class.update(
            record: text_record,
            edit_data: { 'nonexistent' => [{ 'search' => 'x', 'replace' => 'y' }] },
            expected_version: 1,
            user: user
          )
        }.to raise_error(SOT::MutationService::ValidationError, /Unknown field/)
      end

      it 'raises when same field appears in both data and edit_data' do
        expect {
          described_class.update(
            record: text_record,
            data: { 'content' => 'replaced' },
            edit_data: { 'content' => [{ 'search' => 'fox', 'replace' => 'cat' }] },
            expected_version: 1,
            user: user
          )
        }.to raise_error(SOT::MutationService::ValidationError, /both data and edit_data/)
      end

      it 'raises when same field appears in both append_data and edit_data' do
        expect {
          described_class.update(
            record: text_record,
            append_data: { 'content' => ' More text.' },
            edit_data: { 'content' => [{ 'search' => 'fox', 'replace' => 'cat' }] },
            expected_version: 1,
            user: user
          )
        }.to raise_error(SOT::MutationService::ValidationError, /both append_data and edit_data/)
      end

      it 'works alongside data on different fields' do
        result = described_class.update(
          record: text_record,
          data: { 'title' => 'Updated Doc' },
          edit_data: { 'content' => [{ 'search' => 'fox', 'replace' => 'cat' }] },
          expected_version: 1,
          user: user
        )
        expect(result.parsed_data['title']).to eq('Updated Doc')
        expect(result.parsed_data['content']).to eq('The quick brown cat jumps over the lazy dog.')
      end

      it 'matches edits against original text, not post-edit text' do
        rec = described_class.create(
          schema: text_schema,
          data: { 'title' => 'Doc', 'content' => 'aaa bbb ccc' },
          user: user
        )
        result = described_class.update(
          record: rec,
          edit_data: { 'content' => [
            { 'search' => 'aaa', 'replace' => 'XXX' },
            { 'search' => 'ccc', 'replace' => 'ZZZ' }
          ] },
          expected_version: 1,
          user: user
        )
        expect(result.parsed_data['content']).to eq('XXX bbb ZZZ')
      end

      it 'increments version' do
        result = described_class.update(
          record: text_record,
          edit_data: { 'content' => [{ 'search' => 'fox', 'replace' => 'cat' }] },
          expected_version: 1,
          user: user
        )
        expect(result.current_version).to eq(2)
      end

      it 'records correct before/after in activity log' do
        described_class.update(
          record: text_record,
          edit_data: { 'content' => [{ 'search' => 'brown fox', 'replace' => 'red cat' }] },
          expected_version: 1,
          user: user
        )
        logs = SOT::ActivityLog.where(record_id: text_record.id, action: 'update').all
        changes = logs.last.parsed_changes
        expect(changes['before']['data']['content']).to eq('The quick brown fox jumps over the lazy dog.')
        expect(changes['after']['data']['content']).to eq('The quick red cat jumps over the lazy dog.')
      end

      it 'handles symbol keys from MCP gem' do
        result = described_class.update(
          record: text_record,
          edit_data: { content: [{ search: 'fox', replace: 'cat' }] },
          expected_version: 1,
          user: user
        )
        expect(result.parsed_data['content']).to eq('The quick brown cat jumps over the lazy dog.')
      end

      it 'raises when search is empty string' do
        expect {
          described_class.update(
            record: text_record,
            edit_data: { 'content' => [{ 'search' => '', 'replace' => 'x' }] },
            expected_version: 1,
            user: user
          )
        }.to raise_error(SOT::MutationService::ValidationError, /non-empty string/)
      end
    end

    it 'creates an activity log entry with before/after diff' do
      described_class.update(
        record: record,
        data: { 'title' => 'Updated' },
        state: 'closed',
        expected_version: 1,
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
      described_class.delete(record: record, expected_version: 1, user: user)
      expect(SOT::Record[id]).to be_nil
    end

    it 'raises VersionConflict on version mismatch' do
      expect {
        described_class.delete(record: record, expected_version: 99, user: user)
      }.to raise_error(SOT::MutationService::VersionConflict)
    end

    it 'raises ValidationError when version is missing' do
      expect {
        described_class.delete(record: record, user: user)
      }.to raise_error(SOT::MutationService::ValidationError, /version is required/)
    end

    it 'succeeds when preconditions match' do
      expect {
        described_class.delete(
          record: record,
          preconditions: { 'state' => 'open' },
          expected_version: 1,
          user: user
        )
      }.not_to raise_error
    end

    it 'raises PreconditionFailed when preconditions fail' do
      expect {
        described_class.delete(
          record: record,
          preconditions: { 'state' => 'closed' },
          expected_version: 1,
          user: user
        )
      }.to raise_error(SOT::MutationService::PreconditionFailed)
    end

    it 'creates an activity log entry' do
      id = record.id
      described_class.delete(record: record, expected_version: 1, user: user)
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
      described_class.update(record: record.reload, data: { 'title' => 'v2' }, expected_version: 1, user: user)
      described_class.update(record: record.reload, data: { 'title' => 'v3' }, expected_version: 2, user: user)
      described_class.delete(record: record.reload, expected_version: 3, user: user)

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
