Rails.application.routes.draw do
  # controllers: indique à Devise d'utiliser notre controller personnalisé pour l'inscription
  devise_for :users, controllers: { registrations: "users/registrations" }

  # Page d'accueil
  root to: "pages#home"

  # Page "Qui sommes-nous ?"
  get "about", to: "pages#about", as: :about

  # Page "Qui sommes-nous ?" — version 2 (expérimentale)
  get "about2", to: "pages#about2", as: :about2

  # Routes pour les matchs (CRUD complet)
  # Exemple : GET /matches => liste, GET /matches/1 => détail, etc.
  resources :matches do
    # Routes imbriquées pour gérer les inscriptions à un match
    # POST   /matches/:match_id/match_users          => rejoindre
    # DELETE /matches/:match_id/match_users/:id      => quitter
    # PATCH  /matches/:match_id/match_users/:id/approve => approuver (organisateur)
    # PATCH  /matches/:match_id/match_users/:id/reject  => rejeter (organisateur)
    # Route pour envoyer un message dans le chat du match
    # POST /matches/:match_id/messages => crée un message
    resources :messages, only: [:create]

    resources :match_users, only: [:create, :destroy] do
      member do
        patch :approve
        patch :reject
      end
    end
  end

  # Route pour le profil de l'utilisateur connecté (ressource singulière)
  # GET  /profil      => voir mon profil
  # GET  /profil/edit => modifier mon profil
  # PUT  /profil      => sauvegarder les modifications
  resource :profil, only: [:show, :edit, :update]

  # Route pour voir le profil public d'un autre utilisateur
  # GET /users/:id/profil => voir le profil de l'utilisateur avec cet id
  get "users/:id/profil", to: "profils#show_user", as: :user_profil

  # Routes pour les notifications
  # GET   /notifications               => liste des notifications
  # PATCH /notifications/:id/mark_read => marquer une notif comme lue
  # PATCH /notifications/mark_all_read => tout marquer comme lu
  resources :notifications, only: [:index, :destroy] do
    member do
      patch :mark_read
    end
    collection do
      patch :mark_all_read
    end
  end

  # Routes pour le chat sticky global (accessible depuis toutes les pages)
  # GET    /conversations/:id         => chat d'un match spécifique (dans le panneau sticky)
  # DELETE /conversations/:id/dismiss => masquer la conversation (bouton poubelle)
  resources :conversations, only: [:index, :show] do
    member do
      delete :dismiss
    end
  end

  # Route multisport EN PREMIER — doit être avant /:id sinon "all" est capturé comme un id
  post "/switch_sport/all", to: "sports#multisport", as: :multisport_switch

  # Route pour changer le sport actif de l'utilisateur
  # POST /switch_sport/3 → passe au sport avec l'id 3
  post "/switch_sport/:id", to: "sports#switch", as: :switch_sport

  # Route AJAX pour la recherche d'établissements sportifs
  # Appelée par le Stimulus controller "place-search" via fetchDbVenues()
  # GET /venues/search?q=...&lat=...&lon=... → retourne JSON
  get "venues/search", to: "venues#search", as: :search_venues

  # Vérification de santé de l'application
  get "up" => "rails/health#show", as: :rails_health_check
end
