Rails.application.routes.draw do
  devise_for :users

  # Page d'accueil
  root to: "pages#home"

  # Routes pour les matchs (CRUD complet)
  # Exemple : GET /matches => liste, GET /matches/1 => détail, etc.
  resources :matches do
    # Routes imbriquées pour gérer les inscriptions à un match
    # POST   /matches/:match_id/match_users          => rejoindre
    # DELETE /matches/:match_id/match_users/:id      => quitter
    # PATCH  /matches/:match_id/match_users/:id/approve => approuver (organisateur)
    # PATCH  /matches/:match_id/match_users/:id/reject  => rejeter (organisateur)
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

  # Routes pour les notifications
  # GET   /notifications               => liste des notifications
  # PATCH /notifications/:id/mark_read => marquer une notif comme lue
  # PATCH /notifications/mark_all_read => tout marquer comme lu
  resources :notifications, only: [:index] do
    member do
      patch :mark_read
    end
    collection do
      patch :mark_all_read
    end
  end

  # Vérification de santé de l'application
  get "up" => "rails/health#show", as: :rails_health_check
end
