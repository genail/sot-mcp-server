require 'spec_helper'

RSpec.describe SOT::Tools::User::Mutate, type: :tool do
  let(:user) { create(:user) }
  let!(:schema) { create(:table_schema, :stateful, namespace: 'org', name: 'locks', description: 'Resource locks') }

  describe 'create action' do
    it 'creates a record with version 1' do
      response = call_tool(described_class, user: user,
                           action: 'create', table: 'org.locks', data: { 'title' => 'New' })
      expect(response_error?(response)).to be false
      text = response_text(response)
      expect(text).to include('Created record')
      expect(text).to include('(v1)')
      expect(text).to include('New')
    end

    it 'returns error for unknown table' do
      response = call_tool(described_class, user: user,
                           action: 'create', table: 'nonexistent', data: { 'title' => 'x' })
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('not found')
    end

    it 'returns error for missing data' do
      response = call_tool(described_class, user: user,
                           action: 'create', table: 'org.locks')
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include("'data' is required")
    end

    it 'returns schema context on validation error' do
      response = call_tool(described_class, user: user,
                           action: 'create', table: 'org.locks', data: { 'bad' => 'field' })
      expect(response_error?(response)).to be true
      text = response_text(response)
      expect(text).to include('Schema Context')
      expect(text).to include('Resource locks')
      expect(text).to include('sot_feedback')
    end
  end

  describe 'update action' do
    let(:record) do
      SOT::MutationService.create(schema: schema, data: { 'title' => 'Original' }, state: 'open', user: user)
    end

    it 'merges data by default' do
      SOT::MutationService.update(record: record, data: { 'title' => 'Original', 'count' => '3' }, expected_version: 1, user: user, replace_data: true)
      response = call_tool(described_class, user: user,
                           action: 'update', record_id: record.id, data: { 'title' => 'Updated' }, version: 2)
      expect(response_error?(response)).to be false
      refreshed = SOT::Record[record.id]
      expect(refreshed.parsed_data['title']).to eq('Updated')
      expect(refreshed.parsed_data['count']).to eq('3')
    end

    it 'returns updated version in response' do
      response = call_tool(described_class, user: user,
                           action: 'update', record_id: record.id,
                           data: { 'title' => 'Updated' }, version: 1)
      expect(response_error?(response)).to be false
      expect(response_text(response)).to include('(v2)')
    end

    it 'replaces data when replace_data is true' do
      response = call_tool(described_class, user: user,
                           action: 'update', record_id: record.id,
                           data: { 'title' => 'Replaced' }, replace_data: true, version: 1)
      expect(response_error?(response)).to be false
      expect(response_text(response)).to include('Replaced')
    end

    it 'updates with passing preconditions' do
      response = call_tool(described_class, user: user,
                           action: 'update', record_id: record.id,
                           state: 'closed', preconditions: { 'state' => 'open' }, version: 1)
      expect(response_error?(response)).to be false
      expect(response_text(response)).to include('closed')
    end

    it 'returns error on version conflict' do
      response = call_tool(described_class, user: user,
                           action: 'update', record_id: record.id,
                           data: { 'title' => 'New' }, version: 99)
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('Version conflict')
    end

    it 'returns error when version is missing for non-append update' do
      response = call_tool(described_class, user: user,
                           action: 'update', record_id: record.id,
                           data: { 'title' => 'New' })
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('version is required')
    end

    it 'does not modify the record when version is missing' do
      original_data = record.parsed_data.dup
      original_version = record.current_version

      call_tool(described_class, user: user,
                action: 'update', record_id: record.id,
                data: { 'title' => 'Should Not Apply' })

      refreshed = SOT::Record[record.id]
      expect(refreshed.parsed_data).to eq(original_data)
      expect(refreshed.current_version).to eq(original_version)
    end

    it 'returns error with schema context on precondition failure' do
      response = call_tool(described_class, user: user,
                           action: 'update', record_id: record.id,
                           state: 'closed', preconditions: { 'state' => 'closed' }, version: 1)
      expect(response_error?(response)).to be true
      text = response_text(response)
      expect(text).to include('Precondition failed')
      expect(text).to include('Schema Context')
      expect(text).to include('Current record state: open')
      expect(text).to include('sot_feedback')
    end

    it 'appends to a field with append_data (no version required)' do
      schema_with_log = create(:table_schema, namespace: 'org', name: 'tasks',
                               fields: JSON.generate([
                                 { 'name' => 'title', 'type' => 'string', 'required' => true },
                                 { 'name' => 'log', 'type' => 'text', 'required' => false }
                               ]))
      rec = SOT::MutationService.create(schema: schema_with_log, data: { 'title' => 'Task', 'log' => 'Entry 1' }, user: user)
      response = call_tool(described_class, user: user,
                           action: 'update', record_id: rec.id,
                           append_data: { 'log' => "\nEntry 2" })
      expect(response_error?(response)).to be false
      refreshed = SOT::Record[rec.id]
      expect(refreshed.parsed_data['log']).to eq("Entry 1\nEntry 2")
    end

    context 'with edit_data' do
      let(:text_schema) do
        create(:table_schema, namespace: 'org', name: 'docs',
               fields: JSON.generate([
                 { 'name' => 'title', 'type' => 'string', 'required' => true },
                 { 'name' => 'body', 'type' => 'text', 'required' => false }
               ]))
      end

      let(:doc_record) do
        SOT::MutationService.create(schema: text_schema,
                                    data: { 'title' => 'Guide', 'body' => 'Hello world. This is a guide.' },
                                    user: user)
      end

      it 'applies search/replace edit' do
        response = call_tool(described_class, user: user,
                             action: 'update', record_id: doc_record.id,
                             edit_data: { 'body' => [{ 'search' => 'Hello world', 'replace' => 'Hi there' }] },
                             version: 1)
        expect(response_error?(response)).to be false
        refreshed = SOT::Record[doc_record.id]
        expect(refreshed.parsed_data['body']).to eq('Hi there. This is a guide.')
      end

      it 'returns error when search text not found' do
        response = call_tool(described_class, user: user,
                             action: 'update', record_id: doc_record.id,
                             edit_data: { 'body' => [{ 'search' => 'nonexistent', 'replace' => 'x' }] },
                             version: 1)
        expect(response_error?(response)).to be true
        expect(response_text(response)).to include('search text not found')
      end

      it 'returns error when search text is ambiguous' do
        rec = SOT::MutationService.create(schema: text_schema,
                                          data: { 'title' => 'Doc', 'body' => 'foo bar foo' },
                                          user: user)
        response = call_tool(described_class, user: user,
                             action: 'update', record_id: rec.id,
                             edit_data: { 'body' => [{ 'search' => 'foo', 'replace' => 'baz' }] },
                             version: 1)
        expect(response_error?(response)).to be true
        expect(response_text(response)).to include('matches 2 locations')
      end

      it 'requires version' do
        response = call_tool(described_class, user: user,
                             action: 'update', record_id: doc_record.id,
                             edit_data: { 'body' => [{ 'search' => 'Hello', 'replace' => 'Hi' }] })
        expect(response_error?(response)).to be true
        expect(response_text(response)).to include('version is required')
      end
    end

    it 'returns error when append_data targets non-text field' do
      response = call_tool(described_class, user: user,
                           action: 'update', record_id: record.id,
                           append_data: { 'count' => '1' })
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('Cannot append')
    end

    it 'returns error for missing record_id' do
      response = call_tool(described_class, user: user,
                           action: 'update', data: { 'title' => 'x' })
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include("'record_id' is required")
    end

    it 'returns error for nonexistent record' do
      response = call_tool(described_class, user: user,
                           action: 'update', record_id: 99999)
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('not found')
    end
  end

  describe 'delete action' do
    let(:record) do
      SOT::MutationService.create(schema: schema, data: { 'title' => 'ToDelete' }, state: 'open', user: user)
    end

    it 'deletes a record' do
      response = call_tool(described_class, user: user,
                           action: 'delete', record_id: record.id, version: 1)
      expect(response_error?(response)).to be false
      expect(response_text(response)).to include('Deleted')
    end

    it 'returns error on version conflict' do
      response = call_tool(described_class, user: user,
                           action: 'delete', record_id: record.id, version: 99)
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('Version conflict')
    end

    it 'returns error when version is missing' do
      response = call_tool(described_class, user: user,
                           action: 'delete', record_id: record.id)
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('version is required')
    end

    it 'returns error on precondition failure' do
      response = call_tool(described_class, user: user,
                           action: 'delete', record_id: record.id,
                           preconditions: { 'state' => 'closed' }, version: 1)
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('Precondition failed')
    end
  end
end
