class ReplaceRssCommentOption < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      UPDATE feeds
      SET params = (params - 'content_in_comments') || jsonb_build_object(
        'article_presentation',
        CASE WHEN params->'content_in_comments' = 'true'::jsonb
          THEN 'text_in_comment' ELSE 'title_and_text' END
      )
      WHERE feed_profile_key = 'rss' AND NOT params ? 'article_presentation'
    SQL
  end

  def down
    execute <<~SQL
      UPDATE feeds
      SET params = (params - 'article_presentation') || jsonb_build_object(
        'content_in_comments',
        params->>'article_presentation' IN ('text_in_comment', 'text_in_paragraph_comments')
      )
      WHERE feed_profile_key = 'rss' AND params ? 'article_presentation'
    SQL
  end
end
