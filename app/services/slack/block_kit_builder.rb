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

      # Le champ "Format" n'apparaît que si l'organisateur en a choisi un à la
      # création ; sinon on n'affiche que le nombre de joueurs.
      fields = [
        { type: "mrkdwn", text: "*Sport*\n#{sport}" },
        { type: "mrkdwn", text: "*Quand*\n#{match_when_label(match)}" },
        { type: "mrkdwn", text: "*Où*\n#{location_label(match)}" },
        { type: "mrkdwn", text: "*Niveau*\n#{match.level.presence || 'Tout niveau'}" }
      ]
      fields << { type: "mrkdwn", text: "*Format*\n#{match.format}" } if match.format.present?
      fields << { type: "mrkdwn", text: "*Joueurs*\n#{players_label(match)}" }

      [
        { type: "header",
          text: { type: "plain_text", text: "🏆 Nouveau match : #{match.title}", emoji: true } },
        # Tag de statut (À venir / En cours / Terminé), ré-édité par SlackMatchStatusJob.
        { type: "context",
          elements: [{ type: "mrkdwn", text: status_tag(match) }] },
        { type: "section", fields: fields },
        { type: "actions", elements: action_elements(match) }
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

    # Boutons de la carte match. Le bouton d'inscription n'a de sens que si le match
    # est encore à venir ; une fois commencé/terminé, on ne garde que le lien web.
    def action_elements(match)
      view_button = {
        type: "button",
        text: { type: "plain_text", text: "Voir sur Teams-up", emoji: true },
        url: match_url(match)
      }
      return [view_button] unless match_status(match) == :upcoming

      join_button = {
        type: "button",
        style: "primary",
        text: { type: "plain_text", text: "S'inscrire au match", emoji: true },
        # action_id + value : lus par Slack::InteractivityController pour inscrire.
        action_id: "match_join",
        value: match.id.to_s
      }
      [join_button, view_button]
    end

    # Statut du match d'après ses horaires réels :
    #   :upcoming     → n'a pas encore commencé
    #   :in_progress  → entre l'heure de début et l'heure de fin
    #   :completed    → l'heure de fin est passée
    # (basé sur build_datetime / end_datetime, pas sur l'heuristique "+1h" du modèle.)
    def match_status(match)
      start_at = match.build_datetime
      end_at   = match.end_datetime
      return :upcoming if start_at.blank? || start_at > Time.current
      return :in_progress if end_at.blank? || end_at > Time.current

      :completed
    end

    # Libellé mrkdwn du tag de statut affiché en tête de carte.
    def status_tag(match)
      case match_status(match)
      when :in_progress then "🟢 *En cours*"
      when :completed   then "🏁 *Terminé*"
      else                   "🗓️ *À venir*"
      end
    end

    # "Quand" pour un match : date + heure de début, suivie de l'heure de fin
    # si l'organisateur l'a saisie (ex "16/07/2026 à 12:00 → 13:30"). On ne
    # fabrique pas de fin "+1h" par défaut pour ne rien annoncer d'inexact.
    def match_when_label(match)
      base = formatted_datetime(match)
      return base if match.end_time.blank?

      "#{base} → #{match.end_time.strftime('%H:%M')}"
    end

    # Lieu affiché : on combine le nom du terrain et la ville quand ils sont
    # distincts (ex "Stade Charléty · Paris"), sinon on retombe sur ce qu'on a.
    def location_label(match)
      name = match.venue&.name.presence
      city = match.venue&.city.presence

      parts = [name, city].compact.uniq
      return parts.join(" · ") if parts.any?

      match.place.presence || "Lieu à définir"
    end

    # Libellé "inscrits / total" (ex "9/18 personnes"). MÊME calcul que la vue web
    # (matches/_spots) : total = présents + places libres (organisateur inclus),
    # et non `players_needed` qui exclut l'organisateur (d'où un écart d'1).
    def players_label(match)
      present = match.secured_players_count
      total   = present + match.player_left.to_i

      "#{present}/#{total} personnes"
    end
  end
end
