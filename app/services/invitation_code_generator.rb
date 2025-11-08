# frozen_string_literal: true

# Generates invitation codes in "Correct Horse Battery Staple" style
# with word combinations loaded from curated text files.
#
# Examples:
#   bewildered-pangolin-42k
#   tickle-waffle-x7p
#   chartreuse-biscuit-wizard-m3n
class InvitationCodeGenerator
  WORDS_DIR = Rails.root.join("lib/invitation_code_generator/words")

  class << self
    def adjectives
      @adjectives ||= load_words("adjectives.txt")
    end

    def animals
      @animals ||= load_words("animals.txt")
    end

    def verbs
      @verbs ||= load_words("verbs.txt")
    end

    def nouns
      @nouns ||= load_words("nouns.txt")
    end

    def colors
      @colors ||= load_words("colors.txt")
    end

    private

    def load_words(filename)
      File.readlines(WORDS_DIR.join(filename), chomp: true).freeze
    end
  end

  # Pattern templates for code generation
  PATTERNS = [
    ->(g) { "#{g.adjective}-#{g.animal}-#{g.short_hash}" },
    ->(g) { "#{g.verb}-#{g.noun}-#{g.short_hash}" },
    ->(g) { "#{g.color}-#{g.noun}-#{g.tiny_hash}" },
    ->(g) { "#{g.adjective}-#{g.noun}-#{g.number}" },
    ->(g) { "#{g.verb}-#{g.animal}-#{g.tiny_hash}" },
    ->(g) { "#{g.adjective}-#{g.animal}-#{g.number}" }
  ].freeze

  def initialize(random: Random.new)
    @random = random
  end

  # Generate a new invitation code
  def generate
    pattern = PATTERNS.sample(random: @random)
    pattern.call(self)
  end

  # Word accessors for pattern lambdas
  def adjective
    self.class.adjectives.sample(random: @random)
  end

  def animal
    self.class.animals.sample(random: @random)
  end

  def verb
    self.class.verbs.sample(random: @random)
  end

  def noun
    self.class.nouns.sample(random: @random)
  end

  def color
    self.class.colors.sample(random: @random)
  end

  def number
    @random.rand(10..999).to_s
  end

  # Short hash for uniqueness (3 chars)
  def short_hash
    chars = ("a".."z").to_a + ("0".."9").to_a
    3.times.map { chars.sample(random: @random) }.join
  end

  # Tiny hash for uniqueness (2 chars)
  def tiny_hash
    chars = ("a".."z").to_a + ("0".."9").to_a
    2.times.map { chars.sample(random: @random) }.join
  end
end
