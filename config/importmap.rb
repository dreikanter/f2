# Pin npm packages by running ./bin/importmap

pin "application"

# Layout-specific entrypoints: Bootstrap legacy vs. Tailwind migration.
# TBD: When the migration is over, drop the legacy pin and merge tailwind.js to application.js
pin "legacy", to: "legacy.js"
pin "tailwind", to: "tailwind.js"

pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "bootstrap", to: "bootstrap.bundle.min.js"
