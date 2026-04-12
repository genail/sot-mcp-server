require 'spec_helper'

RSpec.describe SOT::SnippetService do
  describe '.extract' do
    it 'returns match with offset and surrounding context' do
      data = { 'content' => 'The quick brown fox jumps over the lazy dog' }
      results = described_class.extract(data, ['fox'], fields: ['content'], context: 10)
      expect(results['content']).not_to be_nil
      matches = results['content']
      expect(matches.length).to eq(1)
      expect(matches[0][:offset]).to eq(16)
      expect(matches[0][:snippet]).to include('fox')
    end

    it 'returns up to 3 matches per field' do
      data = { 'content' => 'aaa bbb aaa bbb aaa bbb aaa bbb aaa' }
      results = described_class.extract(data, ['aaa'], fields: ['content'], context: 2)
      expect(results['content'].length).to eq(3)
    end

    it 'does not exceed 3 matches even with multiple terms' do
      data = { 'content' => 'aaa bbb aaa bbb aaa bbb ccc bbb ccc' }
      results = described_class.extract(data, ['aaa', 'ccc'], fields: ['content'], context: 2)
      expect(results['content'].length).to be <= 3
    end

    it 'merges overlapping snippet windows' do
      # Two matches 5 chars apart with context of 10 — windows overlap
      data = { 'content' => 'xxxxx alpha beta gamma xxxxx' }
      results = described_class.extract(data, ['alpha', 'gamma'], fields: ['content'], context: 15)
      matches = results['content']
      # Should merge into one snippet covering both matches
      expect(matches.length).to eq(1)
      expect(matches[0][:snippet]).to include('alpha')
      expect(matches[0][:snippet]).to include('gamma')
    end

    it 'round-robins across search terms' do
      # 'aaa' appears 3 times, 'zzz' appears once at end
      data = { 'content' => 'aaa ... aaa ... aaa ... zzz' }
      results = described_class.extract(data, ['aaa', 'zzz'], fields: ['content'], context: 2)
      matches = results['content']
      terms_found = matches.map { |m| m[:term] || m[:terms] }.flatten.uniq
      expect(terms_found).to include('zzz')
    end

    it 'matches case-insensitively but preserves original case in snippet' do
      data = { 'content' => 'The Quick Brown FOX jumps' }
      results = described_class.extract(data, ['fox'], fields: ['content'], context: 5)
      snippet = results['content'][0][:snippet]
      expect(snippet).to include('FOX')
    end

    it 'reports no match for fields with no hits' do
      data = { 'content' => 'nothing matches here', 'notes' => 'also nothing' }
      results = described_class.extract(data, ['zzz'], fields: ['content', 'notes'], context: 10)
      expect(results['content']).to eq([])
      expect(results['notes']).to eq([])
    end

    it 'respects context size parameter' do
      data = { 'content' => 'x' * 50 + 'MATCH' + 'y' * 50 }
      results_small = described_class.extract(data, ['match'], fields: ['content'], context: 5)
      results_large = described_class.extract(data, ['match'], fields: ['content'], context: 20)
      small_snippet = results_small['content'][0][:snippet]
      large_snippet = results_large['content'][0][:snippet]
      expect(large_snippet.length).to be > small_snippet.length
    end

    it 'handles match at the beginning of field' do
      data = { 'content' => 'MATCH and then some more text' }
      results = described_class.extract(data, ['match'], fields: ['content'], context: 10)
      expect(results['content'][0][:offset]).to eq(0)
      expect(results['content'][0][:snippet]).to start_with('MATCH')
    end

    it 'handles match at the end of field' do
      data = { 'content' => 'some text and then MATCH' }
      results = described_class.extract(data, ['match'], fields: ['content'], context: 10)
      expect(results['content'][0][:snippet]).to end_with('MATCH')
    end

    it 'skips non-string field values' do
      data = { 'count' => 42, 'content' => 'find me here' }
      results = described_class.extract(data, ['find'], fields: ['count', 'content'], context: 5)
      expect(results['count']).to eq([])
      expect(results['content'].length).to eq(1)
    end

    it 'only searches specified fields' do
      data = { 'title' => 'has the word fox', 'content' => 'also has fox' }
      results = described_class.extract(data, ['fox'], fields: ['content'], context: 5)
      expect(results.keys).to eq(['content'])
    end

    it 'defaults context to 100 when not specified' do
      data = { 'content' => 'x' * 200 + 'MATCH' + 'y' * 200 }
      results = described_class.extract(data, ['match'], fields: ['content'])
      snippet = results['content'][0][:snippet]
      # Should have ~100 chars before + 5 (MATCH) + ~100 chars after
      expect(snippet.length).to be_within(10).of(205)
    end
  end
end
