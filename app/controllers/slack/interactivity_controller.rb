# Reçoit les interactions Slack (POST form-urlencoded, champ `payload` = JSON) :
#   - block_actions   : clic sur un bouton Block Kit (« S'inscrire », action_id "match_join") ;
#   - view_submission : soumission de la modale de création ouverte par /match (callback_id "match_create").
#
# Slack attend une réponse en MOINS DE 3 SECONDES.
#   - block_actions   → on ACK (head :ok) et on délègue l'inscription à SlackEnrollJob.
#   - view_submission → la validation DOIT être synchrone pour renvoyer les erreurs inline
#     (`response_action: "errors"`) ; la création est rapide, seul le post de la carte
#     dans le channel part en job (SlackNotifyJob).
#
# La signature est vérifiée en amont par Slack::BaseController.
module Slack
  class InteractivityController < Slack::BaseController
    def create
      payload = parse_payload
      return head :ok unless payload

      case payload["type"]
      when "block_actions"   then handle_block_actions(payload)
      when "view_submission" then handle_view_submission(payload)
      else head :ok
      end
    end

    private

    # ── block_actions : boutons de la carte match ───────────────────────────────
    # Chaque bouton porte un action_id, mappé vers son job dédié (tous partagent
    # la même signature : match_id, team_id, slack_user_id, response_url).
    ACTION_JOBS = {
      "match_join" => SlackEnrollJob,
      "match_leave" => SlackUnenrollJob,
      "match_cancel" => SlackCancelJob
    }.freeze

    def handle_block_actions(payload)
      action = Array(payload["actions"]).find { |a| ACTION_JOBS.key?(a["action_id"]) }
      return head :ok unless action

      ACTION_JOBS.fetch(action["action_id"]).perform_later(
        match_id: action["value"],
        team_id: payload.dig("team", "id"),
        slack_user_id: payload.dig("user", "id"),
        response_url: payload["response_url"]
      )

      head :ok
    end

    # ── view_submission : soumission de la modale « Créer un match » ─────────────
    def handle_view_submission(payload)
      view = payload["view"]
      return head :ok unless view && view["callback_id"] == Slack::MatchModalBuilder::CALLBACK_ID

      identity = SlackIdentity.for_slack(team_id: payload.dig("team", "id"),
                                         user_id: payload.dig("user", "id"))
      # Ne devrait pas arriver (la modale ne s'ouvre que si lié), mais on ferme proprement.
      return head :ok unless identity

      match = build_match(view, identity.user)

      if match.valid?
        create_and_notify(match, identity, view)
        head :ok # 200 vide → Slack ferme la modale
      else
        render json: { response_action: "errors", errors: error_blocks(match) }
      end
    end

    # Construit (sans sauver) un Match à partir des valeurs saisies dans la modale.
    # Champs forcés (non exposés dans la modale simplifiée) : public + validation auto,
    # aucune restriction de genre (la création par slash reste ouverte à tous en v1).
    def build_match(view, user)
      v  = view.dig("state", "values")
      mb = Slack::MatchModalBuilder

      Match.new(
        user: user,
        sport_id: selected(v, mb::BLOCK_SPORT),
        title: plain(v, mb::BLOCK_TITLE),
        date: picked(v, mb::BLOCK_DATE, "selected_date"),
        time: picked(v, mb::BLOCK_TIME, "selected_time"),
        place: plain(v, mb::BLOCK_PLACE),
        players_needed: plain(v, mb::BLOCK_PLAYERS),
        level: selected(v, mb::BLOCK_LEVEL),
        visibility: "public",
        validation_mode: "automatic",
        genre_restriction: "tous"
      )
    end

    def create_and_notify(match, identity, view)
      MatchCreationService.new(match: match).call

      # Poste la carte du match dans le channel où /match a été tapé.
      channel_id = metadata(view)["channel_id"]
      SlackNotifyJob.perform_later("Match", match.id, identity.user_id,
                                   channel_id.presence, identity.slack_workspace_id)
    end

    # private_metadata transporte le contexte du slash (channel_id, response_url…).
    def metadata(view)
      JSON.parse(view["private_metadata"].to_s)
    rescue JSON::ParserError
      {}
    end

    # Mappe les erreurs de validation du modèle vers les block_id de la modale.
    # Les erreurs sur :base (ex. « au moins 30 min à l'avance ») sont rattachées au bloc date.
    def error_blocks(match)
      mb = Slack::MatchModalBuilder
      field_to_block = {
        sport: mb::BLOCK_SPORT,
        title: mb::BLOCK_TITLE,
        level: mb::BLOCK_LEVEL,
        players_needed: mb::BLOCK_PLAYERS,
        date: mb::BLOCK_DATE,
        time: mb::BLOCK_TIME,
        base: mb::BLOCK_DATE
      }

      errors = {}
      match.errors.group_by_attribute.each do |attribute, attribute_errors|
        block = field_to_block[attribute] || mb::BLOCK_TITLE
        # Un seul message par bloc (Slack n'en affiche qu'un).
        errors[block] ||= attribute_errors.first.full_message
      end
      errors
    end

    # ── Extraction des valeurs Block Kit ─────────────────────────────────────────
    def plain(values, block_id)
      values.dig(block_id, "value", "value").presence
    end

    def selected(values, block_id)
      values.dig(block_id, "value", "selected_option", "value")
    end

    def picked(values, block_id, key)
      values.dig(block_id, "value", key)
    end

    # Le payload interactif arrive dans le champ de formulaire `payload` (JSON).
    def parse_payload
      JSON.parse(params[:payload].to_s)
    rescue JSON::ParserError
      nil
    end
  end
end
