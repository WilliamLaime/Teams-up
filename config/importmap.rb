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

# Leaflet — cartographie interactive (format ESM, compatible importmap-rails)
# Utilisé par map_picker_controller.js pour le sélecteur de lieu sur carte
pin "leaflet", to: "https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet-src.esm.js"
