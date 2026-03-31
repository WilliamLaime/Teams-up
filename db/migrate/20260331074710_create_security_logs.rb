# Migration pour créer la table des logs de sécurité.
# Chaque ligne représente un événement de sécurité (connexion, echec, blocage rack-attack, etc.)
class CreateSecurityLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :security_logs do |t|
      # Lien vers l'utilisateur (optionnel : certains événements n'ont pas d'user connu,
      # ex. une IP bloquée avant même d'avoir tenté de se connecter)
      # on_delete: :nullify → si le user est supprimé, on garde le log mais on met user_id à NULL
      # (l'historique de sécurité ne doit jamais être effacé avec le compte)
      t.references :user, null: true, foreign_key: { on_delete: :nullify }

      # Type d'événement : "login_success", "login_failure", "rack_attack_throttle",
      # "password_reset_request", "signup", "google_login"
      t.string :event_type, null: false

      # Adresse IP de la requête (utile pour détecter une IP malveillante)
      t.string :ip_address

      # User-Agent du navigateur (utile pour détecter les bots ou les crawlers)
      t.string :user_agent

      # Données JSON supplémentaires : email tenté, nom du throttle rack-attack, etc.
      # jsonb (Binary JSON) est plus performant que json sur PostgreSQL → indexable et rapide à requêter
      t.jsonb :details, default: {}

      # created_at uniquement — on ne modifie JAMAIS un log de sécurité après sa création
      t.timestamps
    end

    # Index pour filtrer rapidement par type d'événement (ex: "login_failure")
    add_index :security_logs, :event_type

    # Index pour chercher tous les événements d'une IP suspecte
    add_index :security_logs, :ip_address

    # Index pour les requêtes triées/filtrées par date dans l'admin
    add_index :security_logs, :created_at
  end
end
