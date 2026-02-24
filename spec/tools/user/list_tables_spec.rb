require 'spec_helper'

RSpec.describe SOT::Tools::User::ListTables, type: :tool do
  describe '.call' do
    it 'returns all schemas' do
      create(:table_schema, namespace: 'org', name: 'locks', description: 'Resource locks')
      create(:table_schema, namespace: 'org', name: 'docs', description: 'Documentation')
      response = call_tool(described_class)
      text = response_text(response)
      expect(text).to include('org.locks')
      expect(text).to include('org.docs')
      expect(text).to include('Resource locks')
    end

    it 'filters by namespace' do
      create(:table_schema, namespace: 'org', name: 'locks')
      create(:table_schema, namespace: 'project', name: 'tasks')
      response = call_tool(described_class, namespace: 'org')
      text = response_text(response)
      expect(text).to include('org.locks')
      expect(text).not_to include('project.tasks')
    end

    it 'shows field descriptions' do
      create(:table_schema)
      response = call_tool(described_class)
      text = response_text(response)
      expect(text).to include('title (string) (required)')
      expect(text).to include('count (integer)')
    end

    it 'shows state descriptions for stateful schemas' do
      create(:table_schema, :stateful)
      response = call_tool(described_class)
      text = response_text(response)
      expect(text).to include('States:')
      expect(text).to include('open')
    end

    it 'shows Stateless for stateless schemas' do
      create(:table_schema)
      response = call_tool(described_class)
      text = response_text(response)
      expect(text).to include('Stateless')
    end

    it 'handles no schemas' do
      response = call_tool(described_class)
      text = response_text(response)
      expect(text).to include('No tables found')
    end
  end
end
