module EventReferencedWebSearches
  extend ActiveSupport::Concern

  private

  def referenced_web_searches(event)
    WebSearchUsage.referenced_by(event)
  end
end
