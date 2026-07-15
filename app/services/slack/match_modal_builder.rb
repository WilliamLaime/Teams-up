# Construit la vue Block Kit de la modale « Créer un match » ouverte par /match.
#
# Version SIMPLIFIÉE par rapport au formulaire web : pas de géoloc (le lieu est
# du texte libre → Match#place, jamais de venue_id), pas de format d'équipe, pas
# de visibilité/mode de validation (forcés public + automatic à la soumission).
#
# `callback_id` identifie la modale à la soumission (view_submission), et
# `private_metadata` transporte le contexte nécessaire pour poster la carte du
# match dans le bon channel après création (le view_submission ne renvoie ni
# channel_id ni response_url par lui-même).
module Slack
  class MatchModalBuilder
    CALLBACK_ID = "match_create".freeze

    # Blocs de saisie identifiés par block_id → relus tels quels dans view.state.values.
    BLOCK_SPORT   = "sport".freeze
    BLOCK_TITLE   = "title".freeze
    BLOCK_DATE    = "date".freeze
    BLOCK_TIME    = "time".freeze
    BLOCK_PLACE   = "place".freeze
    BLOCK_PLAYERS = "players_needed".freeze
    BLOCK_LEVEL   = "level".freeze

    # Niveaux proposés. « Tout niveau » est toujours valide (compat modèle) ; les
    # niveaux nommés ne conviennent qu'aux sports à échelle généraliste (collectifs).
    # Un choix incompatible avec le sport est rattrapé en erreur inline à la soumission.
    LEVELS = ["Tout niveau", "Débutant", "Amateur", "Intermédiaire", "Confirmé", "Expert"].freeze

    # @param channel_id [String] channel où /match a été tapé (destination de la carte)
    # @param response_url [String] URL éphémère du slash (confirmation post-création)
    # @param team_id [String] workspace Slack (résolution du bot token à l'envoi)
    def initialize(channel_id:, response_url:, team_id:)
      @channel_id   = channel_id
      @response_url = response_url
      @team_id      = team_id
    end

    def view
      {
        type: "modal",
        callback_id: CALLBACK_ID,
        private_metadata: { channel_id: @channel_id, response_url: @response_url, team_id: @team_id }.to_json,
        title:  { type: "plain_text", text: "Créer un match" },
        submit: { type: "plain_text", text: "Créer" },
        close:  { type: "plain_text", text: "Annuler" },
        blocks: blocks
      }
    end

    private

    def blocks
      [
        input(BLOCK_SPORT, "Sport", static_select("Choisis un sport", sport_options)),
        input(BLOCK_TITLE, "Titre",
              { type: "plain_text_input", action_id: "value", max_length: 100 }),
        input(BLOCK_DATE, "Date",
              { type: "datepicker", action_id: "value", initial_date: Date.tomorrow.iso8601 }),
        input(BLOCK_TIME, "Heure",
              { type: "timepicker", action_id: "value", initial_time: "18:00" }),
        input(BLOCK_PLAYERS, "Joueurs recherchés",
              { type: "number_input", action_id: "value", is_decimal_allowed: false, min_value: "1" }),
        input(BLOCK_LEVEL, "Niveau", static_select("Choisis un niveau", level_options)),
        input(BLOCK_PLACE, "Lieu",
              { type: "plain_text_input", action_id: "value", max_length: 255 }, optional: true)
      ]
    end

    # Un bloc `input` Block Kit (label + élément de saisie).
    def input(block_id, label, element, optional: false)
      { type: "input", block_id: block_id, optional: optional,
        label: { type: "plain_text", text: label }, element: element }
    end

    def static_select(placeholder, options)
      { type: "static_select", action_id: "value",
        placeholder: { type: "plain_text", text: placeholder }, options: options }
    end

    def sport_options
      Sport.order(:name).map do |sport|
        { text: { type: "plain_text", text: sport.name }, value: sport.id.to_s }
      end
    end

    def level_options
      LEVELS.map { |level| { text: { type: "plain_text", text: level }, value: level } }
    end
  end
end
