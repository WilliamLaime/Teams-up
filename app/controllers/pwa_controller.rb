# Controller PWA — sert le manifest et le service worker avec le bon Content-Type
# On hérite de ActionController::Base (et non ApplicationController) pour éviter :
# - la protection CSRF qui bloque les fichiers JS servis directement
# - les callbacks Devise/Pundit qui ne s'appliquent pas ici
class PwaController < ActionController::Base
  # Désactive la vérification cross-origin pour les fichiers JS/JSON publics du PWA
  # Sans ça, Rails lève InvalidCrossOriginRequest quand le service worker est chargé
  skip_forgery_protection

  # GET /manifest.json
  # Retourne le manifeste PWA au format JSON
  def manifest
    # formats: [:json] → Rails cherche le fichier manifest.json.erb (pas manifest.html.erb)
    render template: "pwa/manifest", layout: false, content_type: "application/json", formats: [:json]
  end

  # GET /service-worker
  # formats: [:js] → Rails cherche le fichier service-worker.js (pas service-worker.html.erb)
  def service_worker
    render template: "pwa/service-worker", layout: false, content_type: "text/javascript", formats: [:js]
  end
end
