# frozen_string_literal: true

require "test_helper"

class InvitationCodeGeneratorTest < ActiveSupport::TestCase
  test "#generate should return a non-empty string" do
    generator = InvitationCodeGenerator.new
    code = generator.generate

    assert_kind_of String, code
    assert code.present?
  end

  test "#generate should produce codes with hyphens separating components" do
    generator = InvitationCodeGenerator.new
    code = generator.generate

    assert_match(/-/, code, "Code should contain at least one hyphen")
  end

  test "#generate should produce deterministic codes with seeded random" do
    random1 = Random.new(12345)
    random2 = Random.new(12345)

    generator1 = InvitationCodeGenerator.new(random: random1)
    generator2 = InvitationCodeGenerator.new(random: random2)

    code1 = generator1.generate
    code2 = generator2.generate

    assert_equal code1, code2
  end

  test "#generate should produce different codes with different seeds" do
    random1 = Random.new(11111)
    random2 = Random.new(22222)

    generator1 = InvitationCodeGenerator.new(random: random1)
    generator2 = InvitationCodeGenerator.new(random: random2)

    code1 = generator1.generate
    code2 = generator2.generate

    assert_not_equal code1, code2
  end

  test "#generate should produce codes with components from curated word lists" do
    generator = InvitationCodeGenerator.new
    codes = 20.times.map { generator.generate }

    all_words = [
      InvitationCodeGenerator::ADJECTIVES,
      InvitationCodeGenerator::ANIMALS,
      InvitationCodeGenerator::VERBS,
      InvitationCodeGenerator::NOUNS,
      InvitationCodeGenerator::COLORS,
      InvitationCodeGenerator::OBJECTS,
      InvitationCodeGenerator::SUFFIXES
    ].flatten

    codes.each do |code|
      components = code.split("-")
      # At least one component should be from our word lists
      word_found = components.any? { |component| all_words.include?(component) }
      assert word_found, "Code '#{code}' should contain at least one word from curated lists"
    end
  end

  test "#generate should produce reasonably unique codes" do
    generator = InvitationCodeGenerator.new
    codes = 100.times.map { generator.generate }

    # With our word lists and random suffixes, we should see good variety
    unique_count = codes.uniq.length
    assert unique_count >= 90, "Expected at least 90% uniqueness, got #{unique_count}/100"
  end

  test "#generate should produce codes matching expected pattern format" do
    generator = InvitationCodeGenerator.new
    code = generator.generate

    # Should match general pattern: word-word-suffix or word-word-word-suffix
    # where suffix is alphanumeric
    assert_match(/\A[a-z]+-[a-z]+(-[a-z]+)?-[a-z0-9]+\z/, code,
                 "Code should match expected pattern format")
  end

  test "#generate should produce codes with reasonable length" do
    generator = InvitationCodeGenerator.new
    codes = 50.times.map { generator.generate }

    codes.each do |code|
      assert code.length >= 10, "Code '#{code}' should be at least 10 characters"
      assert code.length <= 60, "Code '#{code}' should be at most 60 characters"
    end
  end

  test "#adjective should return word from adjectives list" do
    generator = InvitationCodeGenerator.new
    adjective = generator.adjective

    assert_includes InvitationCodeGenerator::ADJECTIVES, adjective
  end

  test "#animal should return word from animals list" do
    generator = InvitationCodeGenerator.new
    animal = generator.animal

    assert_includes InvitationCodeGenerator::ANIMALS, animal
  end

  test "#verb should return word from verbs list" do
    generator = InvitationCodeGenerator.new
    verb = generator.verb

    assert_includes InvitationCodeGenerator::VERBS, verb
  end

  test "#noun should return word from nouns list" do
    generator = InvitationCodeGenerator.new
    noun = generator.noun

    assert_includes InvitationCodeGenerator::NOUNS, noun
  end

  test "#color should return word from colors list" do
    generator = InvitationCodeGenerator.new
    color = generator.color

    assert_includes InvitationCodeGenerator::COLORS, color
  end

  test "#object should return word from objects list" do
    generator = InvitationCodeGenerator.new
    object = generator.object

    assert_includes InvitationCodeGenerator::OBJECTS, object
  end

  test "#suffix should return word from suffixes list" do
    generator = InvitationCodeGenerator.new
    suffix = generator.suffix

    assert_includes InvitationCodeGenerator::SUFFIXES, suffix
  end

  test "#number should return numeric string between 10 and 999" do
    generator = InvitationCodeGenerator.new
    number = generator.number

    assert_match(/\A\d+\z/, number, "Number should be all digits")
    num_value = number.to_i
    assert num_value >= 10, "Number should be at least 10"
    assert num_value <= 999, "Number should be at most 999"
  end

  test "#short_hash should return 3-character alphanumeric string" do
    generator = InvitationCodeGenerator.new
    hash = generator.short_hash

    assert_equal 3, hash.length
    assert_match(/\A[a-z0-9]{3}\z/, hash)
  end

  test "#tiny_hash should return 2-character alphanumeric string" do
    generator = InvitationCodeGenerator.new
    hash = generator.tiny_hash

    assert_equal 2, hash.length
    assert_match(/\A[a-z0-9]{2}\z/, hash)
  end
end
