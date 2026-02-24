require 'spec_helper'

RSpec.describe SOT::Tools::User::DescribeTables, type: :tool do
  describe 'summary mode (default)' do
    it 'returns table names and descriptions' do
      create(:table_schema, namespace: 'org', name: 'locks', description: 'Resource locks')
      create(:table_schema, namespace: 'org', name: 'docs', description: 'Documentation')
      response = call_tool(described_class)
      text = response_text(response)
      expect(text).to include('org.locks')
      expect(text).to include('org.docs')
      expect(text).to include('Resource locks')
      expect(text).to include('Documentation')
    end

    it 'does not include field details' do
      create(:table_schema)
      response = call_tool(described_class)
      text = response_text(response)
      expect(text).not_to include('Fields:')
      expect(text).not_to include('(string)')
    end

    it 'indicates stateful tables' do
      create(:table_schema, :stateful, namespace: 'org', name: 'locks')
      response = call_tool(described_class)
      text = response_text(response)
      expect(text).to include('(stateful)')
    end

    it 'filters by namespace' do
      create(:table_schema, namespace: 'org', name: 'locks')
      create(:table_schema, namespace: 'project', name: 'tasks')
      response = call_tool(described_class, namespace: 'org')
      text = response_text(response)
      expect(text).to include('org.locks')
      expect(text).not_to include('project.tasks')
    end

    it 'handles no tables' do
      response = call_tool(described_class)
      text = response_text(response)
      expect(text).to include('No tables found')
    end
  end

  describe 'detail mode (detail: true)' do
    it 'shows field details for all tables' do
      create(:table_schema, namespace: 'org', name: 'locks')
      response = call_tool(described_class, detail: true)
      text = response_text(response)
      expect(text).to include('Fields:')
      expect(text).to include('title (string) (required)')
      expect(text).to include('count (integer)')
    end

    it 'shows state details for stateful tables' do
      create(:table_schema, :stateful)
      response = call_tool(described_class, detail: true)
      text = response_text(response)
      expect(text).to include('States:')
      expect(text).to include('open')
    end

    it 'shows Stateless for stateless tables' do
      create(:table_schema)
      response = call_tool(described_class, detail: true)
      text = response_text(response)
      expect(text).to include('Stateless')
    end

    it 'filters by namespace' do
      create(:table_schema, namespace: 'org', name: 'locks')
      create(:table_schema, namespace: 'project', name: 'tasks')
      response = call_tool(described_class, detail: true, namespace: 'org')
      text = response_text(response)
      expect(text).to include('org.locks')
      expect(text).not_to include('project.tasks')
    end
  end

  describe 'selected tables mode (tables: [...])' do
    it 'shows full detail for selected tables only' do
      create(:table_schema, namespace: 'org', name: 'locks', description: 'Resource locks')
      create(:table_schema, namespace: 'org', name: 'docs', description: 'Documentation')
      response = call_tool(described_class, tables: ['org.locks'])
      text = response_text(response)
      expect(text).to include('org.locks')
      expect(text).to include('Fields:')
      expect(text).not_to include('org.docs')
    end

    it 'describes multiple selected tables' do
      create(:table_schema, namespace: 'org', name: 'locks')
      create(:table_schema, namespace: 'org', name: 'docs')
      response = call_tool(described_class, tables: ['org.locks', 'org.docs'])
      text = response_text(response)
      expect(text).to include('org.locks')
      expect(text).to include('org.docs')
      expect(text).to include('Fields:')
    end

    it 'reports tables not found' do
      create(:table_schema, namespace: 'org', name: 'locks')
      response = call_tool(described_class, tables: ['org.locks', 'nonexistent'])
      text = response_text(response)
      expect(text).to include('org.locks')
      expect(text).to include('Tables not found: nonexistent')
    end

    it 'reports all not found when none match' do
      response = call_tool(described_class, tables: ['nonexistent'])
      text = response_text(response)
      expect(text).to include('Tables not found: nonexistent')
      expect(text).to include('sot_describe_tables')
    end
  end
end
