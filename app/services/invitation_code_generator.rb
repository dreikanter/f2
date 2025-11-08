# frozen_string_literal: true

# Generates invitation codes in "Correct Horse Battery Staple" style
# with mildly absurd, Monty Python-esque word combinations.
#
# Examples:
#   bewildered-pangolin-42k
#   tickle-waffle-x7p
#   chartreuse-biscuit-wizard-m3n
class InvitationCodeGenerator
  # Curated word lists for mildly absurd combinations
  ADJECTIVES = %w[
    bewildered cosmic elder suspicious vigilant
    quantum peculiar dubious reluctant magnificent
    anxious startled perplexed baffled mystified
  ].freeze

  ANIMALS = %w[
    pangolin llama newt hedgehog stoat
    badger wombat platypus narwhal axolotl
    capybara tapir quokka manatee dugong
  ].freeze

  VERBS = %w[
    tickle wiggle ponder dangle stumble
    fumble waddle shuffle bobble twiddle
    wobble fidget hobble bumble scuttle
  ].freeze

  NOUNS = %w[
    waffle banana toaster biscuit kettle
    spoon crumpet marmalade custard pudding
    teapot scone muffin pickle radish
  ].freeze

  COLORS = %w[
    chartreuse beige mauve taupe crimson
    ochre vermillion cerulean umber sienna
    indigo magenta teal burgundy cobalt
  ].freeze

  OBJECTS = %w[
    sock waffle biscuit kettle spoon
    monocle umbrella trowel bucket spanner
    thimble widget gadget contraption doohickey
  ].freeze

  SUFFIXES = %w[
    ninja wizard sage prophet oracle
    baron duke earl knight squire
    maestro captain admiral commander chief
  ].freeze

  # Pattern templates for code generation
  PATTERNS = [
    ->(g) { "#{g.adjective}-#{g.animal}-#{g.short_hash}" },
    ->(g) { "#{g.verb}-#{g.noun}-#{g.short_hash}" },
    ->(g) { "#{g.color}-#{g.object}-#{g.suffix}-#{g.tiny_hash}" },
    ->(g) { "#{g.adjective}-#{g.noun}-#{g.number}" },
    ->(g) { "#{g.verb}-#{g.animal}-#{g.tiny_hash}" }
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
    ADJECTIVES.sample(random: @random)
  end

  def animal
    ANIMALS.sample(random: @random)
  end

  def verb
    VERBS.sample(random: @random)
  end

  def noun
    NOUNS.sample(random: @random)
  end

  def color
    COLORS.sample(random: @random)
  end

  def object
    OBJECTS.sample(random: @random)
  end

  def suffix
    SUFFIXES.sample(random: @random)
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
