# Simple, dependency-free "is this basically the same string" check used to
# warn on likely-duplicate project/task titles. Not meant to be a general
# NLP similarity measure - just a plain edit-distance ratio.
module StringSimilarity
  DEFAULT_THRESHOLD = 0.85

  def self.similar?(a, b, threshold: DEFAULT_THRESHOLD)
    ratio(a, b) >= threshold
  end

  def self.ratio(a, b)
    a = a.to_s.strip.downcase
    b = b.to_s.strip.downcase
    return 1.0 if a == b
    return 0.0 if a.empty? || b.empty?

    distance = levenshtein_distance(a, b)
    longer_length = [a.length, b.length].max
    1.0 - (distance.to_f / longer_length)
  end

  # Standard iterative (Wagner-Fischer) edit distance: minimum number of
  # single-character insertions/deletions/substitutions to turn `a` into `b`.
  def self.levenshtein_distance(a, b)
    costs = (0..b.length).to_a

    a.each_char.with_index do |char_a, i|
      costs[0] = i + 1
      prev_diagonal = i

      b.each_char.with_index do |char_b, j|
        prev_diagonal_for_next = costs[j + 1]
        costs[j + 1] = if char_a == char_b
          prev_diagonal
        else
          [costs[j], costs[j + 1], prev_diagonal].min + 1
        end
        prev_diagonal = prev_diagonal_for_next
      end
    end

    costs[b.length]
  end
end
