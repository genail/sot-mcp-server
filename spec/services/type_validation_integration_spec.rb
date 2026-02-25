require 'spec_helper'

RSpec.describe 'Type validation integration' do
  let(:user) { create(:user) }

  describe 'MutationService with typed fields' do
    context 'integer fields' do
      let(:schema) do
        create(:table_schema, fields: JSON.generate([
          { 'name' => 'title', 'type' => 'string', 'required' => true },
          { 'name' => 'count', 'type' => 'integer', 'required' => false }
        ]))
      end

      it 'coerces integer value to string on create' do
        record = SOT::MutationService.create(
          schema: schema, data: { 'title' => 'Test', 'count' => 42 }, user: user
        )
        expect(record.parsed_data['count']).to eq('42')
      end

      it 'coerces string integer on create' do
        record = SOT::MutationService.create(
          schema: schema, data: { 'title' => 'Test', 'count' => '42' }, user: user
        )
        expect(record.parsed_data['count']).to eq('42')
      end

      it 'rejects invalid integer on create' do
        expect {
          SOT::MutationService.create(
            schema: schema, data: { 'title' => 'Test', 'count' => 'abc' }, user: user
          )
        }.to raise_error(SOT::MutationService::ValidationError, /count.*cannot coerce/)
      end

      it 'coerces integer on update (only touched field validated)' do
        record = SOT::MutationService.create(
          schema: schema, data: { 'title' => 'Test', 'count' => '5' }, user: user
        )
        result = SOT::MutationService.update(
          record: record, data: { 'count' => 10 }, expected_version: 1, user: user
        )
        expect(result.parsed_data['count']).to eq('10')
      end
    end

    context 'boolean fields' do
      let(:schema) do
        create(:table_schema, fields: JSON.generate([
          { 'name' => 'title', 'type' => 'string', 'required' => true },
          { 'name' => 'active', 'type' => 'boolean', 'required' => false }
        ]))
      end

      it 'coerces true boolean' do
        record = SOT::MutationService.create(
          schema: schema, data: { 'title' => 'Test', 'active' => true }, user: user
        )
        expect(record.parsed_data['active']).to eq('true')
      end

      it 'coerces "yes" to "true"' do
        record = SOT::MutationService.create(
          schema: schema, data: { 'title' => 'Test', 'active' => 'yes' }, user: user
        )
        expect(record.parsed_data['active']).to eq('true')
      end

      it 'rejects invalid boolean' do
        expect {
          SOT::MutationService.create(
            schema: schema, data: { 'title' => 'Test', 'active' => 'maybe' }, user: user
          )
        }.to raise_error(SOT::MutationService::ValidationError, /active.*cannot coerce.*boolean/)
      end
    end

    context 'datetime fields' do
      let(:schema) do
        create(:table_schema, fields: JSON.generate([
          { 'name' => 'title', 'type' => 'string', 'required' => true },
          { 'name' => 'due_at', 'type' => 'datetime', 'required' => false }
        ]))
      end

      it 'normalizes datetime to ISO 8601 UTC' do
        record = SOT::MutationService.create(
          schema: schema,
          data: { 'title' => 'Test', 'due_at' => '2026-02-25T17:00:00+02:00' },
          user: user
        )
        expect(record.parsed_data['due_at']).to eq('2026-02-25T15:00:00Z')
      end

      it 'rejects datetime without timezone' do
        expect {
          SOT::MutationService.create(
            schema: schema,
            data: { 'title' => 'Test', 'due_at' => '2026-02-25T15:00:00' },
            user: user
          )
        }.to raise_error(SOT::MutationService::ValidationError, /due_at.*timezone/)
      end
    end

    context 'user fields' do
      let!(:assignee) { create(:user, name: 'Alice') }
      let(:schema) do
        create(:table_schema, fields: JSON.generate([
          { 'name' => 'title', 'type' => 'string', 'required' => true },
          { 'name' => 'assignee', 'type' => 'user', 'required' => false }
        ]))
      end

      it 'accepts a valid user name' do
        record = SOT::MutationService.create(
          schema: schema,
          data: { 'title' => 'Test', 'assignee' => 'Alice' },
          user: user
        )
        expect(record.parsed_data['assignee']).to eq('Alice')
      end

      it 'rejects non-existent user name' do
        expect {
          SOT::MutationService.create(
            schema: schema,
            data: { 'title' => 'Test', 'assignee' => 'Nobody' },
            user: user
          )
        }.to raise_error(SOT::MutationService::ValidationError, /assignee.*not found/)
      end

      it 'accepts deactivated user name' do
        assignee.update(is_active: false)
        record = SOT::MutationService.create(
          schema: schema,
          data: { 'title' => 'Test', 'assignee' => 'Alice' },
          user: user
        )
        expect(record.parsed_data['assignee']).to eq('Alice')
      end
    end

    context 'backwards compatibility: update only validates touched fields' do
      let(:schema) do
        create(:table_schema, fields: JSON.generate([
          { 'name' => 'title', 'type' => 'string', 'required' => true },
          { 'name' => 'count', 'type' => 'integer', 'required' => false }
        ]))
      end

      it 'allows updating title when count has old invalid data' do
        # Simulate old data that was stored before type validation existed
        record = SOT::Record.create(
          schema_id: schema.id,
          data: JSON.generate({ 'title' => 'Old', 'count' => 'not_a_number' }),
          version: 1,
          created_by: user.id,
          updated_by: user.id
        )

        # Updating only 'title' should succeed even though 'count' is invalid
        result = SOT::MutationService.update(
          record: record,
          data: { 'title' => 'New Title' },
          expected_version: 1,
          user: user
        )
        expect(result.parsed_data['title']).to eq('New Title')
        expect(result.parsed_data['count']).to eq('not_a_number')
      end

      it 'rejects updating the invalid field itself' do
        record = SOT::Record.create(
          schema_id: schema.id,
          data: JSON.generate({ 'title' => 'Old', 'count' => 'not_a_number' }),
          version: 1,
          created_by: user.id,
          updated_by: user.id
        )

        expect {
          SOT::MutationService.update(
            record: record,
            data: { 'count' => 'still_not_a_number' },
            expected_version: 1,
            user: user
          )
        }.to raise_error(SOT::MutationService::ValidationError, /count.*cannot coerce/)
      end
    end
  end

  describe 'SchemaService type change precheck' do
    let(:schema) do
      create(:table_schema, fields: JSON.generate([
        { 'name' => 'title', 'type' => 'string', 'required' => true },
        { 'name' => 'count', 'type' => 'string', 'required' => false }
      ]))
    end

    it 'allows type change when all values are compatible' do
      SOT::MutationService.create(
        schema: schema, data: { 'title' => 'Test', 'count' => '42' }, user: user
      )

      expect {
        SOT::SchemaService.update(schema, fields: [
          { 'name' => 'title', 'type' => 'string', 'required' => true },
          { 'name' => 'count', 'type' => 'integer', 'required' => false }
        ])
      }.not_to raise_error
    end

    it 'rejects type change when values are incompatible' do
      SOT::MutationService.create(
        schema: schema, data: { 'title' => 'Test', 'count' => 'not_a_number' }, user: user
      )

      expect {
        SOT::SchemaService.update(schema, fields: [
          { 'name' => 'title', 'type' => 'string', 'required' => true },
          { 'name' => 'count', 'type' => 'integer', 'required' => false }
        ])
      }.to raise_error(ArgumentError, /Cannot change field types.*incompatible/)
    end

    it 'lists which records are incompatible' do
      record = SOT::MutationService.create(
        schema: schema, data: { 'title' => 'Test', 'count' => 'hello' }, user: user
      )

      expect {
        SOT::SchemaService.update(schema, fields: [
          { 'name' => 'title', 'type' => 'string', 'required' => true },
          { 'name' => 'count', 'type' => 'integer', 'required' => false }
        ])
      }.to raise_error(ArgumentError, /Record ##{record.id}/)
    end

    it 'allows type change when no records exist' do
      expect {
        SOT::SchemaService.update(schema, fields: [
          { 'name' => 'title', 'type' => 'string', 'required' => true },
          { 'name' => 'count', 'type' => 'integer', 'required' => false }
        ])
      }.not_to raise_error
    end

    it 'allows adding new fields with any type (not a type change)' do
      expect {
        SOT::SchemaService.update(schema, fields: [
          { 'name' => 'title', 'type' => 'string', 'required' => true },
          { 'name' => 'count', 'type' => 'string', 'required' => false },
          { 'name' => 'due_at', 'type' => 'datetime', 'required' => false }
        ])
      }.not_to raise_error
    end

    it 'skips nil values during type change check' do
      SOT::MutationService.create(
        schema: schema, data: { 'title' => 'Test' }, user: user  # count is nil
      )

      expect {
        SOT::SchemaService.update(schema, fields: [
          { 'name' => 'title', 'type' => 'string', 'required' => true },
          { 'name' => 'count', 'type' => 'integer', 'required' => false }
        ])
      }.not_to raise_error
    end
  end

  describe 'UserService.rename cascade' do
    let(:admin) { create(:user, is_admin: true) }
    let!(:alice) { create(:user, name: 'Alice') }

    let(:schema_with_user_field) do
      create(:table_schema, fields: JSON.generate([
        { 'name' => 'title', 'type' => 'string', 'required' => true },
        { 'name' => 'assignee', 'type' => 'user', 'required' => false }
      ]))
    end

    let(:schema_without_user_field) do
      create(:table_schema, fields: JSON.generate([
        { 'name' => 'title', 'type' => 'string', 'required' => true },
        { 'name' => 'count', 'type' => 'integer', 'required' => false }
      ]))
    end

    it 'renames the user' do
      SOT::UserService.rename(alice, new_name: 'Alice Smith', admin_user: admin)
      expect(alice.reload.name).to eq('Alice Smith')
    end

    it 'updates user-type fields referencing the old name' do
      record = SOT::MutationService.create(
        schema: schema_with_user_field,
        data: { 'title' => 'Task', 'assignee' => 'Alice' },
        user: admin
      )

      SOT::UserService.rename(alice, new_name: 'Alice Smith', admin_user: admin)

      expect(record.reload.parsed_data['assignee']).to eq('Alice Smith')
    end

    it 'does not affect records without user-type fields' do
      record = SOT::MutationService.create(
        schema: schema_without_user_field,
        data: { 'title' => 'Alice', 'count' => '5' },
        user: admin
      )

      SOT::UserService.rename(alice, new_name: 'Alice Smith', admin_user: admin)

      # 'title' contains 'Alice' but it's a string field, not a user field
      expect(record.reload.parsed_data['title']).to eq('Alice')
    end

    it 'does not affect records where the user-type field has a different user' do
      bob = create(:user, name: 'Bob')
      record = SOT::MutationService.create(
        schema: schema_with_user_field,
        data: { 'title' => 'Task', 'assignee' => 'Bob' },
        user: admin
      )

      SOT::UserService.rename(alice, new_name: 'Alice Smith', admin_user: admin)

      expect(record.reload.parsed_data['assignee']).to eq('Bob')
    end

    it 'increments record version on cascade update' do
      record = SOT::MutationService.create(
        schema: schema_with_user_field,
        data: { 'title' => 'Task', 'assignee' => 'Alice' },
        user: admin
      )
      original_version = record.current_version

      SOT::UserService.rename(alice, new_name: 'Alice Smith', admin_user: admin)

      expect(record.reload.current_version).to eq(original_version + 1)
    end

    it 'creates activity log entries for cascade updates' do
      record = SOT::MutationService.create(
        schema: schema_with_user_field,
        data: { 'title' => 'Task', 'assignee' => 'Alice' },
        user: admin
      )

      SOT::UserService.rename(alice, new_name: 'Alice Smith', admin_user: admin)

      logs = SOT::ActivityLog.where(record_id: record.id, action: 'update').all
      cascade_log = logs.last
      expect(cascade_log.parsed_changes['before']['data']['assignee']).to eq('Alice')
      expect(cascade_log.parsed_changes['after']['data']['assignee']).to eq('Alice Smith')
    end

    it 'rejects rename to blank name' do
      expect {
        SOT::UserService.rename(alice, new_name: '', admin_user: admin)
      }.to raise_error(ArgumentError, /blank/)
    end

    it 'rejects rename to same name' do
      expect {
        SOT::UserService.rename(alice, new_name: 'Alice', admin_user: admin)
      }.to raise_error(ArgumentError, /same/)
    end

    it 'rejects rename to existing user name' do
      create(:user, name: 'Bob')
      expect {
        SOT::UserService.rename(alice, new_name: 'Bob', admin_user: admin)
      }.to raise_error(ArgumentError, /already exists/)
    end

    it 'updates multiple user-type fields in the same record' do
      schema = create(:table_schema, fields: JSON.generate([
        { 'name' => 'title', 'type' => 'string', 'required' => true },
        { 'name' => 'assignee', 'type' => 'user', 'required' => false },
        { 'name' => 'reporter', 'type' => 'user', 'required' => false }
      ]))

      record = SOT::MutationService.create(
        schema: schema,
        data: { 'title' => 'Bug', 'assignee' => 'Alice', 'reporter' => 'Alice' },
        user: admin
      )

      SOT::UserService.rename(alice, new_name: 'Alice Smith', admin_user: admin)

      data = record.reload.parsed_data
      expect(data['assignee']).to eq('Alice Smith')
      expect(data['reporter']).to eq('Alice Smith')
    end
  end
end
