# Lets a maintenance job's description carry markup — the dev area renders it as
# HTML above the job's run history.
#
# Composing through these helpers is what keeps a description safe: the parts a
# job interpolates are escaped, and only the tags it builds here are markup.
module DescribesWithMarkup
  extend ActiveSupport::Concern

  class_methods do
    private

    # The view's tag builders, reachable from a job class.
    def helpers = ApplicationController.helpers
  end
end
