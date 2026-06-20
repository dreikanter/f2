# Pin npm packages by running ./bin/importmap

pin "application"

pin "tailwind", to: "tailwind.js"
pin "flowbite", to: "https://cdn.jsdelivr.net/npm/flowbite@4.0.1/dist/flowbite.turbo.min.js", preload: true

pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

pin "tippy.js", to: "https://esm.sh/tippy.js@6"
pin "date-fns", to: "https://esm.sh/date-fns@4"
