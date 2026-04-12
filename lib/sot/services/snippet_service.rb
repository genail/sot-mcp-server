module SOT
  class SnippetService
    DEFAULT_CONTEXT = 100
    MAX_MATCHES_PER_FIELD = 3

    # Extract match snippets from record data for specified fields.
    #
    # @param data [Hash] parsed record data (field_name => value)
    # @param search_terms [Array<String>] normalized search terms
    # @param fields [Array<String>] field names to extract snippets from
    # @param context [Integer] characters before/after each match
    # @return [Hash<String, Array<Hash>>] field_name => array of match hashes
    #   Each match hash: { offset:, snippet:, term: } or { offset:, snippet:, terms: [] }
    def self.extract(data, search_terms, fields:, context: DEFAULT_CONTEXT)
      fields.each_with_object({}) do |field_name, result|
        value = data[field_name]
        unless value.is_a?(String)
          result[field_name] = []
          next
        end

        candidates = find_all_candidates(value, search_terms)
        selected = select_top_matches(candidates, search_terms)
        windows = build_windows(selected, value, context)
        merged = merge_overlapping(windows, value)
        result[field_name] = merged.first(MAX_MATCHES_PER_FIELD)
      end
    end

    private

    # Find all match positions for all terms in a field value.
    def self.find_all_candidates(value, search_terms)
      downcased = value.downcase
      candidates = []

      search_terms.each do |term|
        term_down = term.downcase
        search_from = 0
        while (pos = downcased.index(term_down, search_from))
          candidates << { offset: pos, length: term.length, term: term }
          search_from = pos + term_down.length
        end
      end

      candidates.sort_by { |c| c[:offset] }
    end

    # Select top matches using round-robin across terms, capped at MAX_MATCHES_PER_FIELD.
    def self.select_top_matches(candidates, search_terms)
      return [] if candidates.empty?

      by_term = {}
      search_terms.each { |t| by_term[t] = [] }
      candidates.each { |c| by_term[c[:term]] << c }

      selected = []
      used_offsets = Set.new
      terms_with_matches = search_terms.select { |t| by_term[t].any? }

      while selected.length < MAX_MATCHES_PER_FIELD
        added_this_round = false
        terms_with_matches.each do |term|
          break if selected.length >= MAX_MATCHES_PER_FIELD
          candidate = by_term[term].shift
          next unless candidate
          unless used_offsets.include?(candidate[:offset])
            selected << candidate
            used_offsets << candidate[:offset]
            added_this_round = true
          end
        end
        break unless added_this_round
      end

      selected.sort_by { |s| s[:offset] }
    end

    # Build snippet windows around each match.
    def self.build_windows(matches, value, context)
      matches.map do |m|
        win_start = [m[:offset] - context, 0].max
        win_end = [m[:offset] + m[:length] + context, value.length].min

        {
          offset: m[:offset],
          term: m[:term],
          win_start: win_start,
          win_end: win_end
        }
      end
    end

    # Merge overlapping or adjacent windows, then extract snippet text.
    def self.merge_overlapping(windows, value)
      return [] if windows.empty?

      sorted = windows.sort_by { |w| w[:win_start] }
      merged = [sorted.first.dup]

      sorted[1..].each do |w|
        prev = merged.last
        if w[:win_start] <= prev[:win_end]
          prev[:win_end] = [prev[:win_end], w[:win_end]].max
          prev_terms = Array(prev[:terms] || [prev[:term]])
          prev_terms << w[:term] unless prev_terms.include?(w[:term])
          prev[:terms] = prev_terms
          prev.delete(:term)
          prev[:offset] = [prev[:offset], w[:offset]].min
        else
          merged << w.dup
        end
      end

      merged.map do |w|
        snippet = value[w[:win_start]...w[:win_end]]
        result = { offset: w[:offset], snippet: snippet }
        if w[:terms]
          result[:terms] = w[:terms]
        else
          result[:term] = w[:term]
        end
        result
      end
    end
  end
end
