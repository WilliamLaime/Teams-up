# Construit les messages Block Kit (format riche de Slack) pour les matchs et tournois.
#
# Les URLs doivent être ABSOLUES : ce code tourne dans un job (SlackNotifyJob), sans
# objet `request` pour deviner l'hôte. On utilise donc les helpers `*_url` (et non
# `*_path`), qui s'appuient sur default_url_options[:host] (voir config/environments).
module Slack
  class BlockKitBuilder
    include Rails.application.routes.url_helpers

    # ── Match créé ────────────────────────────────────────────────────────────
    # Header + détails + bouton "S'inscrire" (interactivity) + lien "Voir sur Teams-up".
    def match_created_blocks(match)
      sport = match.sport&.name || "Sport"
      city  = match.venue&.city || match.place.presence || "Lieu à définir"

      [
        { type: "header",
          text: { type: "plain_text", text: "🏆 Nouveau match : #{match.title}", emoji: true } },
        { type: "section",
          fields: [
            { type: "mrkdwn", text: "*Sport*\n#{sport}" },
            { type: "mrkdwn", text: "*Quand*\n#{formatted_datetime(match)}" },
            { type: "mrkdwn", text: "*Où*\n#{city}" },
            { type: "mrkdwn", text: "*Niveau*\n#{match.level.presence || 'Tout niveau'}" },
            { type: "mrkdwn", text: "*Places restantes*\n#{spots_label(match)}" }
          ] },
        { type: "actions",
          elements: [
            { type: "button",
              style: "primary",
              text: { type: "plain_text", text: "S'inscrire", emoji: true },
              # action_id + value : lus par Slack::InteractivityController pour inscrire.
              action_id: "match_join",
              value: match.id.to_s },
            { type: "button",
              text: { type: "plain_text", text: "Voir sur Teams-up", emoji: true },
              url: match_url(match) }
          ] }
      ]
    end

    # Texte de repli (notif mobile / accessibilité) pour un match.
    def match_created_text(match)
      "Nouveau match : #{match.title} — #{formatted_datetime(match)}"
    end

    # ── Tournoi créé ──────────────────────────────────────────────────────────
    # En v1, pas de bouton d'inscription (l'inscription tournoi reste sur le web) :
    # seulement un lien vers la page du tournoi.
    def tournament_created_blocks(tournament)
      sport = tournament.sport&.name || "Sport"

      [
        { type: "header",
          text: { type: "plain_text", text: "🎲 Nouveau tournoi : #{tournament.name}", emoji: true } },
        { type: "section",
          fields: [
            { type: "mrkdwn", text: "*Sport*\n#{sport}" },
            { type: "mrkdwn", text: "*Format*\n#{tournament.format}" },
            { type: "mrkdwn", text: "*Quand*\n#{formatted_datetime(tournament)}" },
            { type: "mrkdwn", text: "*Lieu*\n#{tournament.place.presence || 'À définir'}" }
          ] },
        { type: "actions",
          elements: [
            { type: "button",
              style: "primary",
              text: { type: "plain_text", text: "Voir le tournoi", emoji: true },
              url: tournament_url(tournament) }
          ] }
      ]
    end

    def tournament_created_text(tournament)
      "Nouveau tournoi : #{tournament.name}"
    end

    private

    # Formate date + heure de façon lisible ("15/07/2026 à 18:30").
    def formatted_datetime(record)
      date = record.date&.strftime("%d/%m/%Y")
      time = record.time&.strftime("%H:%M")
      [date, time].compact.join(" à ").presence || "Date à définir"
    end

    # Libellé des places restantes, robuste si player_left n'est pas calculé.
    def spots_label(match)
      left = match.player_left
      return "#{left} place#{'s' if left.to_i > 1}" if left.present?

      match.players_needed.present? ? "#{match.players_needed} joueurs" : "—"
    end
  end
end
