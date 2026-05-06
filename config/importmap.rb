# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "bootstrap", to: "bootstrap.min.js", preload: true
pin "@popperjs/core", to: "popper.js", preload: true
pin "@rails/actioncable", to: "actioncable.esm.js"

# Sentry Browser SDK — monitoring des erreurs JavaScript en production
# Chargé via CDN jsDelivr (format ESM, compatible importmap-rails)
pin "@sentry/browser", to: "https://cdn.jsdelivr.net/npm/@sentry/browser@8/+esm"
