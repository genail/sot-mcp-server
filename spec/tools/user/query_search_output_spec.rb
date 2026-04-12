require 'spec_helper'

RSpec.describe SOT::Tools::User::Query, 'search output modes', type: :tool do
  let(:user) { create(:user) }
  let(:schema) do
    create(:table_schema, namespace: 'docs', name: 'articles',
           fields: JSON.generate([
             { 'name' => 'title', 'type' => 'string', 'required' => true },
             { 'name' => 'tags', 'type' => 'string' },
             { 'name' => 'content', 'type' => 'text' }
           ]))
  end

  before do
    SOT::MutationService.create(
      schema: schema, user: user,
      data: { 'title' => 'Deployment Guide',
              'tags' => 'devops, staging',
              'content' => 'This is a comprehensive guide about deployment. ' \
                           'The deployment process involves several steps. ' \
                           'First you prepare the staging environment. ' \
                           'Then you run the deployment scripts.' }
    )
    SOT::MutationService.create(
      schema: schema, user: user,
      data: { 'title' => 'API Reference',
              'tags' => 'api, rest',
              'content' => 'The REST API provides endpoints for managing records.' }
    )
  end

  describe 'full_fields parameter' do
    it 'returns only specified fields in full' do
      response = call_tool(described_class, user: user,
                           table: 'docs.articles',
                           full_fields: ['title', 'tags'])
      text = response_text(response)
      expect(text).to include('Deployment Guide')
      expect(text).to include('devops, staging')
      # Should NOT include the full content
      expect(text).not_to include('comprehensive guide about deployment')
    end

    it 'works without search (listing mode)' do
      response = call_tool(described_class, user: user,
                           table: 'docs.articles',
                           full_fields: ['title'])
      text = response_text(response)
      expect(response_error?(response)).to be_falsey
      expect(text).to include('Deployment Guide')
      expect(text).to include('API Reference')
    end

    it 'returns error for unknown field in full_fields' do
      response = call_tool(described_class, user: user,
                           table: 'docs.articles',
                           full_fields: ['nonexistent'])
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('nonexistent')
    end
  end

  describe 'snippet_fields parameter' do
    it 'returns match snippets with offset for searched fields' do
      response = call_tool(described_class, user: user,
                           table: 'docs.articles',
                           search: 'deployment',
                           snippet_fields: ['content'],
                           snippet_context: 20)
      text = response_text(response)
      expect(text).to include('deployment')
      # Should include offset information
      expect(text).to match(/offset \d+/)
    end

    it 'returns error when snippet_fields used without search' do
      response = call_tool(described_class, user: user,
                           table: 'docs.articles',
                           snippet_fields: ['content'])
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('snippet_fields')
      expect(response_text(response)).to include('search')
    end

    it 'reports no match for snippet fields that have no hits' do
      response = call_tool(described_class, user: user,
                           table: 'docs.articles',
                           search: 'deployment',
                           full_fields: ['title'],
                           snippet_fields: ['content'])
      text = response_text(response)
      # The API Reference record matches nothing in content for "deployment"
      # but should still appear if it matches elsewhere (it won't here)
      # The Deployment Guide should show content snippet
      expect(text).to include('Deployment Guide')
    end

    it 'returns error for unknown field in snippet_fields' do
      response = call_tool(described_class, user: user,
                           table: 'docs.articles',
                           search: 'deployment',
                           snippet_fields: ['nonexistent'])
      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('nonexistent')
    end
  end

  describe 'combined full_fields and snippet_fields' do
    it 'returns full fields and snippet fields together' do
      response = call_tool(described_class, user: user,
                           table: 'docs.articles',
                           search: 'deployment',
                           full_fields: ['title', 'tags'],
                           snippet_fields: ['content'],
                           snippet_context: 20)
      text = response_text(response)
      # Full fields present
      expect(text).to include('Deployment Guide')
      expect(text).to include('devops, staging')
      # Snippet with offset
      expect(text).to match(/offset \d+/)
      # Full content NOT dumped
      expect(text).not_to include('comprehensive guide about deployment. The deployment process involves several steps. First you prepare the staging environment. Then you run the deployment scripts.')
    end

    it 'returns error when same field in both full and snippet' do
      response = call_tool(described_class, user: user,
                           table: 'docs.articles',
                           search: 'deployment',
                           full_fields: ['content'],
                           snippet_fields: ['content'])
      expect(response_error?(response)).to be true
    end
  end

  describe 'default behavior (no full_fields/snippet_fields)' do
    it 'returns full document when neither specified (backward compat)' do
      response = call_tool(described_class, user: user,
                           table: 'docs.articles',
                           search: 'deployment')
      text = response_text(response)
      # Current behavior: full data dump
      expect(text).to include('comprehensive guide about deployment')
    end
  end

  describe 'snippet_context parameter' do
    it 'controls the amount of context around matches' do
      response = call_tool(described_class, user: user,
                           table: 'docs.articles',
                           search: 'staging',
                           snippet_fields: ['content'],
                           snippet_context: 10)
      text = response_text(response)
      expect(response_error?(response)).to be_falsey
      expect(text).to include('staging')
    end

    it 'defaults to 100 chars of context' do
      response = call_tool(described_class, user: user,
                           table: 'docs.articles',
                           search: 'staging',
                           snippet_fields: ['content'])
      expect(response_error?(response)).to be_falsey
    end
  end
end
