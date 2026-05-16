# Detects which FeedProfile candidates apply to a user's raw input,
# returning a deterministic ranked list per
# specs/001-smart-feed-creation/contracts/detection.md.
#
# Detection is pure with respect to AI: no LlmClient call may originate
# from a matcher's #match?. The Thread.current[:llm_detection_phase]
# flag is set for the duration of #call so LlmClient (when introduced)
# can enforce that rule.
class FeedProfileDetector
  DetectionResult = Data.define(:input_shape, :candidates)
  DetectionCandidate = Data.define(:profile_key, :title, :depends_on_ai, :rank, :rank_reason)

  def self.call(input:, fetched_body: nil)
    new(input: input, fetched_body: fetched_body).call
  end

  def initialize(input:, fetched_body: nil)
    @input = input
    @fetched_body = fetched_body
  end

  def call
    shape = InputClassifier.classify(@input)
    return empty_result(shape) if shape == :malformed

    Thread.current[:llm_detection_phase] = true

    matches = collect_matches(shape)
    ranked = rank(matches)
    DetectionResult.new(input_shape: shape, candidates: build_candidates(ranked))
  ensure
    Thread.current[:llm_detection_phase] = nil
  end

  private

  attr_reader :input, :fetched_body

  def empty_result(shape)
    DetectionResult.new(input_shape: shape, candidates: [])
  end

  def collect_matches(shape)
    FeedProfile.matchers_for(shape).each_with_index.filter_map do |matcher_class, registration_index|
      begin
        next nil unless matcher_class.new(input, fetched_body).match?
      rescue StandardError => e
        Rails.error.report(e, context: { matcher_class: matcher_class.name, input_shape: shape })
        next nil
      end

      {
        profile_key: matcher_class.profile_key,
        match_specificity: matcher_class.match_specificity,
        depends_on_ai: matcher_class.depends_on_ai,
        registration_index: registration_index
      }
    end
  end

  def rank(matches)
    matches.sort_by do |m|
      [m[:depends_on_ai] ? 1 : 0, -m[:match_specificity], m[:registration_index]]
    end
  end

  def build_candidates(ranked)
    ranked.each_with_index.map do |match, idx|
      DetectionCandidate.new(
        profile_key: match[:profile_key],
        title: extract_title(match[:profile_key]),
        depends_on_ai: match[:depends_on_ai],
        rank: idx,
        rank_reason: rank_reason_for(match, idx)
      )
    end
  end

  def rank_reason_for(match, idx)
    return :ai_fallback if match[:depends_on_ai]

    idx.zero? ? :specific_match : :generic_match
  end

  def extract_title(profile_key)
    return nil unless FeedProfile[profile_key]&.dig(:title_extractor)

    title_class = FeedProfile.title_extractor_class_for(profile_key)
    title_class.new(input, fetched_body).title
  rescue StandardError => e
    Rails.error.report(e, context: { profile_key: profile_key, source: "title_extraction" })
    nil
  end
end
