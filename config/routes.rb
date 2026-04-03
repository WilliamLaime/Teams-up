Rails.application.routes.draw do
  # controllers: indique à Devise d'utiliser notre controller personnalisé pour l'inscription
  devise_for :users, controllers: {
    registrations:      "users/registrations",      # Controller personnalisé pour l'inscription
    sessions:           "users/sessions",           # Controller personnalisé pour log sécurité + captcha connexion
    passwords:          "users/passwords",          # Controller personnalisé pour log sécurité + captcha reset
    omniauth_callbacks: "users/omniauth_callbacks"  # Controller pour gérer le retour de Google OAuth
  }

  # Page d'accueil
  root to: "pages#home"

  # Page "Qui sommes-nous ?"
  get "quisommesnous", to: "pages#about", as: :about

  # Page de contact — GET affiche le formulaire, POST traite l'envoi
  get  "contact", to: "pages#contact",         as: :contact
  post "contact", to: "contact_messages#create"

  # Page partenariat — présente les opportunités de collaboration professionnelle
  get "partenariat", to: "pages#partenariat", as: :partenariat

  # Page Politique de confidentialité (RGPD)
  get "confidentialite", to: "pages#confidentialite", as: :confidentialite

  # Page Conditions générales d'utilisation
  get "conditions", to: "pages#conditions", as: :conditions

  # ── Équipes ────────────────────────────────────────────────────────────────
  # GET    /teams              → mes équipes
  # GET    /teams/new          → formulaire création
  # POST   /teams              → créer une équipe
  # GET    /teams/:id          → page détail
  # GET    /teams/:id/edit     → modifier l'équipe
  # PATCH  /teams/:id          → sauvegarder les modifs
  # DELETE /teams/:id          → supprimer l'équipe (captain seulement)
  resources :teams do
    member do
      # PATCH /teams/:id/transfer_captain → transférer le capitanat à un autre membre
      patch :transfer_captain
      # DELETE /teams/:id/leave → quitter l'équipe (membres non-captain)
      delete :leave
    end

    # Invitations imbriquées dans l'équipe
    # POST  /teams/:team_id/team_invitations        → inviter un user
    # PATCH /teams/:team_id/team_invitations/:id    → accepter ou refuser
    resources :team_invitations, only: [:create, :update, :destroy] do
      collection do
        # GET /teams/:team_id/team_invitations/search?q=lucas → autocomplete JSON
        get :search
      end
    end

    # Membres imbriqués (retirer un membre)
    # DELETE /teams/:team_id/team_members/:id       → retirer un membre (captain)
    resources :team_members, only: [:destroy]
  end

  # Routes pour les matchs (CRUD complet)
  # Exemple : GET /matches => liste, GET /matches/1 => détail, etc.
  resources :matches do
    member do
      # Télécharge le fichier ICS pour ajouter le match à un calendrier externe
      get :calendar
      # Passe un match privé en public (organisateur uniquement)
      patch :make_public
    end

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
        patch :confirm  # Membre d'équipe qui confirme sa propre place (team match)
      end
    end

    # Vote "homme du match" — POST /matches/:match_id/match_votes
    resources :match_votes, only: [:create]
  end

  # Route pour le profil de l'utilisateur connecté (ressource singulière)
  # GET  /profil        => voir mon profil (version gaming)
  # GET  /profil/simple => voir mon profil (version simplifiée, sans gamification)
  # GET  /profil/edit   => modifier mon profil
  # PUT  /profil        => sauvegarder les modifications
  resource :profil, only: [:show, :edit, :update] do
    # PATCH /profil/spend_stat?attribute=attr_attack => dépenser un point de stat
    patch :spend_stat, on: :member
    # GET /profil/simple => nouvelle page profil sans gamification
    get :simple, on: :member, action: :show_simple
  end

  # Route pour voir le profil public d'un autre utilisateur
  # GET /users/:id/profil        => version gaming
  # GET /users/:id/profil/simple => version simplifiée, sans gamification
  get "users/:id/profil", to: "profils#show_user", as: :user_profil
  get "users/:id/profil/simple", to: "profils#show_user_simple", as: :user_profil_simple

  # Routes pour les avis et les amis (imbriquées sous users)
  # POST   /users/:user_id/avis                => laisser un avis à un joueur
  # POST   /users/:user_id/friendship          => envoyer une demande d'ami
  # DELETE /users/:user_id/friendship          => annuler la demande / retirer l'ami
  # PATCH  /users/:user_id/friendship/accept   => accepter la demande reçue
  # PATCH  /users/:user_id/friendship/decline  => refuser la demande reçue
  resources :users, only: [] do
    resources :avis, only: [:create]
    # Ressource singulière — les actions accept/decline sont des routes collection
    # car la ressource singulière n'a pas d'id dans l'URL
    resource :friendship, only: [:create, :destroy] do
      collection do
        patch :accept
        patch :decline
      end
    end
  end

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

  # Routes pour les conversations privées (1-to-1 entre deux utilisateurs)
  # POST /private_conversations             => crée ou retrouve la conversation (depuis un profil)
  # GET  /private_conversations/:id         => charge le chat dans le panneau sticky
  # POST /private_conversations/:id/messages => envoie un message privé
  resources :private_conversations, only: [:show, :create] do
    member do
      patch  :mark_read  # Marque comme lu (appelé depuis chat_controller.js)
      delete :dismiss    # Masque la conversation (bouton poubelle sidebar)
    end
    resources :messages, only: [:create]
  end

  # Route multisport EN PREMIER — doit être avant /:id sinon "all" est capturé comme un id
  post "/switch_sport/all", to: "sports#multisport", as: :multisport_switch

  # Route pour changer le sport actif de l'utilisateur
  # POST /switch_sport/3 → passe au sport avec l'id 3
  post "/switch_sport/:id", to: "sports#switch", as: :switch_sport

  # Route AJAX pour la recherche d'établissements sportifs
  # Appelée par le Stimulus controller "place-search" via fetchDbVenues()
  # GET /venues/search?q=...&lat=...&lon=... → retourne JSON
  get  "venues/search",          to: "venues#search",          as: :search_venues
  # Appelée quand l'user sélectionne un résultat Nominatim (pas en BDD)
  # POST /venues/find_or_create → cherche par name+city ou crée, retourne { id, name, city }
  post "venues/find_or_create",  to: "venues#find_or_create",  as: :find_or_create_venue

  # ── Espace Admin ───────────────────────────────────────────────────────────
  # GET /admin          → redirige vers le dashboard
  # GET /admin/dashboard → tableau de bord avec les KPIs
  namespace :admin do
    root to: "dashboard#show"
    resource :dashboard, only: [:show]

    # Logs de sécurité (connexions, échecs, blocages rack-attack)
    # GET /admin/security_logs => tableau avec filtres par type et date
    resources :security_logs, only: [:index]

    # Messages reçus via le formulaire /contact
    # GET  /admin/contact_messages          => liste tous les messages
    # PATCH /admin/contact_messages/:id/toggle_lu => bascule lu/non-lu
    resources :contact_messages, only: [:index, :destroy] do
      member do
        patch :toggle_lu
        patch :mark_read  # Marque comme lu quand on clique "Lire" (ouvre la modale)
        post :reply
      end
      collection do
        # DELETE /admin/contact_messages/destroy_all → supprime tous les messages
        delete :destroy_all
      end
    end
  end

  # Vérification de santé de l'application
  get "up" => "rails/health#show", as: :rails_health_check

  # ── Routes PWA ────────────────────────────────────────────────────────────
  # /manifest.json   → renvoie le fichier app/views/pwa/manifest.json.erb (Content-Type: JSON)
  # /service-worker  → renvoie le fichier app/views/pwa/service-worker.js (Content-Type: JS)
  # On utilise notre propre PwaController car rails/pwa ne définit pas le bon format
  get "manifest"       => "pwa#manifest",       as: :pwa_manifest
  get "service-worker" => "pwa#service_worker", as: :pwa_service_worker

  # Page hors-ligne : affichée par le service worker quand l'utilisateur est offline
  get "offline", to: "pages#offline", as: :offline

  # ── Pages d'erreur personnalisées ──────────────────────────────────────────
  # Ces routes sont utilisées par config.exceptions_app = routes (dans application.rb)
  # Rails redirige automatiquement les erreurs vers ces URLs selon le code HTTP
  # /404 → ressource introuvable (match supprimé, route inexistante)
  # /500 → erreur serveur interne
  match "/404", to: "errors#not_found",            via: :all
  match "/500", to: "errors#internal_server_error", via: :all
end
