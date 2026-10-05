module Normalizer
  module CommentSplitting
    private

    # Split without truncation; a sentence longer than the limit falls back
    # to a word boundary, then a hard split for unbroken text.
    def split_comment(text)
      remaining = text.strip
      comments = []
      while remaining.present?
        boundary = comment_boundary(remaining)
        comments << remaining.slice!(0, boundary).rstrip
        remaining = remaining.lstrip
      end
      comments
    end

    def comment_boundary(text)
      limit = Post::MAX_COMMENT_LENGTH
      return text.length if text.length <= limit

      excerpt = text[0, limit + 1]
      excerpt.rindex(/\n\n/) || excerpt.rindex(/\n/) ||
        excerpt.rindex(/[.!?]["”’']?\K\s+/) || excerpt.rindex(/\s+/) || limit
    end
  end
end
