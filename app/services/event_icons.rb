# Per-event-type icons for the event log, loaded from config/event_icons.yml.
#
# Lets an entry's icon say what happened (an envelope for mail events) instead
# of only how severe it was. Types without an entry — and entries naming an
# icon the app doesn't bundle — resolve to nil so callers fall back to the
# level-based icon; a stale or misspelled configuration can never leave an
# entry without an icon.
class EventIcons
  PATH = Rails.root.join("config/event_icons.yml")

  class << self
    def icon_for(type)
      name = table[type.to_s]
      name if name && ApplicationHelper::ICONS.key?(name)
    end

    private

    def table
      @table ||= load_table
    end

    def load_table
      return {} unless File.exist?(PATH)

      YAML.safe_load(File.read(PATH)) || {}
    end
  end
end
