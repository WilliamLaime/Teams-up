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
    #
    # Deux mises en page, parce que les deux cartes ne répondent pas à la même
    # question. Un match OUVERT dit « peux-tu venir jouer ? » : il lui faut le
    # niveau, le compteur de places et la liste des inscrits, qui grandit. Une
    # rencontre de TOURNOI dit « qui joue, quand, et qui a gagné ? » : les deux
    # adversaires sont fixés par le tirage, la carte n'a donc que quatre choses à
    # dire et tient en deux lignes de champs.
    def match_created_blocks(match)
      [
        { type: "header",
          text: { type: "plain_text", text: card_title(match), emoji: true } },
        # Tag de statut (À venir / En cours / Terminé + résultat), ré-édité par
        # SlackMatchStatusJob à chaque changement d'état ou de score.
        { type: "context",
          elements: [{ type: "mrkdwn", text: status_tag(match) }] },
        { type: "section", fields: detail_fields(match) },
        # Liste des inscrits : réservée aux matchs ouverts (sur une confrontation,
        # les adversaires sont déjà dans les champs ci-dessus).
        *enrolled_block(match),
        { type: "actions", elements: action_elements(match) }
      ]
    end

    # Emoji de tête de carte : celui du sport quand il est connu (🏓 en ping-pong,
    # ⚽ en foot — cf. db/sports.rb), sinon la coupe générique.
    def match_emoji(match)
      match.sport&.icon.presence || "🏆"
    end

    # Texte de repli (notif mobile / accessibilité) pour un match. C'est ce que
    # lisent la notification push et le lecteur d'écran : quand le score est
    # tombé, c'est LUI l'information, pas la date de la rencontre.
    def match_created_text(match)
      tmatch = match.tournament_confrontation? ? match.tournament_match : nil
      return "#{match.title} — score final #{tmatch.score_summary}" if tmatch&.score_entered?

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

    # ── Rappel "préparez-vous" (~15 min avant le coup d'envoi) ──────────────────
    # Nouveau message (pas une ré-édition de la carte) posté dans le(s) même(s)
    # channel(s) que la carte du match. `mentions` (optionnel) = chaîne "<@U…> <@U…>"
    # des joueurs dont le compte Slack est lié, pour les notifier nommément.
    # `opponent` (optionnel) : le User d'en face, quand le rappel part en message
    # privé à un joueur précis (rencontre de tournoi). Dans ce cas on ne met pas
    # de mention `<@U…>` — le destinataire est déjà seul dans la conversation,
    # se pinguer soi-même n'a pas de sens.
    def match_prep_blocks(match, mentions = nil, opponent: nil)
      lines = ["*#{match.title}* démarre dans ~15 min. À vous de jouer ! 💪"]
      lines << "🆚 Tu affrontes *#{opponent.short_name}*" if opponent.present?
      lines << "📍 #{location_label(match)}"
      lines << mentions if mentions.present?

      [
        { type: "header",
          text: { type: "plain_text", text: "⏰ Ça commence bientôt !", emoji: true } },
        { type: "section", text: { type: "mrkdwn", text: lines.join("\n") } },
        { type: "actions",
          elements: [
            { type: "button",
              text: { type: "plain_text", text: "Voir sur Teams-up", emoji: true },
              url: match_url(match) }
          ] }
      ]
    end

    def match_prep_text(match)
      "Ton match \"#{match.title}\" commence dans un quart d'heure — prépare-toi !"
    end

    # ── Carte "match annulé" ────────────────────────────────────────────────────
    # Le match est supprimé lors de l'annulation → la carte devient un simple
    # avis figé (ni ratio, ni boutons), construit à partir du seul titre capturé
    # avant destruction.
    def match_cancelled_blocks(title)
      [
        { type: "header",
          text: { type: "plain_text", text: "🚫 Match annulé", emoji: true } },
        { type: "section",
          text: { type: "mrkdwn",
                  text: "*#{title}*\n_Ce match a été annulé par l'organisateur._" } }
      ]
    end

    def match_cancelled_text(title)
      "Le match \"#{title}\" a été annulé."
    end

    # ── Liste "annuler un match" (réponse éphémère de /match-cancel) ────────────
    # Liste des matchs à venir de l'organisateur, chacun avec un bouton
    # « Annuler » (action_id match_cancel, organisateur vérifié côté
    # SlackCancelJob). N'étant renvoyée qu'en éphémère, elle n'est visible que de
    # l'auteur de la commande → le bouton reste privé à l'organisateur.
    def cancel_list_blocks(matches)
      if matches.empty?
        return [{ type: "section",
                  text: { type: "mrkdwn", text: "Tu n'as aucun match à venir à annuler." } }]
      end

      blocks = [{ type: "section",
                  text: { type: "mrkdwn", text: "*Tes matchs à venir* — choisis celui à annuler :" } }]

      matches.each do |match|
        blocks << {
          type: "section",
          text: { type: "mrkdwn",
                  text: "*#{match.title}*\n#{match_when_label(match)} · #{location_label(match)}" },
          accessory: {
            type: "button",
            style: "danger",
            text: { type: "plain_text", text: "Annuler", emoji: true },
            action_id: "match_cancel",
            value: match.id.to_s,
            confirm: {
              title: { type: "plain_text", text: "Annuler ce match ?" },
              text: { type: "mrkdwn", text: "Les joueurs inscrits seront prévenus. Action irréversible." },
              confirm: { type: "plain_text", text: "Annuler le match" },
              deny: { type: "plain_text", text: "Retour" }
            }
          }
        }
      end

      blocks
    end

    private

    # Titre de la carte. « Nouveau match : » n'a de sens qu'une fois : la carte
    # est ré-éditée sur place à chaque changement (statut, score), et une
    # confrontation dont le score est tombé n'est plus « nouvelle ». Son titre
    # (« Ping-Pong — Léa Martin vs Tom Roux ») se suffit d'ailleurs à lui-même.
    def card_title(match)
      prefix = match.tournament_confrontation? ? "" : "Nouveau match : "

      "#{match_emoji(match)} #{prefix}#{match.title}"
    end

    # Champs à deux colonnes du bloc de détails. Slack les remplit DE GAUCHE À
    # DROITE, deux par ligne : l'ordre du tableau est donc l'ordre à l'écran.
    #
    # Confrontation de tournoi — deux lignes, rien de superflu :
    #     Quand        | Adversaires (ou Score, une fois joué)
    #     Où           | Format
    # Le sport n'y a plus de champ dédié : l'emoji de tête et le titre le disent
    # déjà deux fois. Niveau et compteur de places répondent à « puis-je
    # m'inscrire ? », question qui ne se pose pas sur une rencontre tirée au sort.
    def detail_fields(match)
      if match.tournament_confrontation?
        fields = [
          { type: "mrkdwn", text: "*Quand*\n#{match_when_label(match)}" },
          { type: "mrkdwn", text: opponents_label(match) },
          { type: "mrkdwn", text: "*Où*\n#{location_label(match)}" }
        ]
        fields << { type: "mrkdwn", text: "*Format*\n#{match.format}" } if match.format.present?
        return fields
      end

      fields = [
        { type: "mrkdwn", text: "*Sport*\n#{match.sport&.name || 'Sport'}" },
        { type: "mrkdwn", text: "*Quand*\n#{match_when_label(match)}" },
        { type: "mrkdwn", text: "*Où*\n#{location_label(match)}" }
      ]
      # Un match seulement rattaché à un tournoi (sélecteur du Descriptif, sans
      # carte du tableau) reste ouvert aux inscriptions mais n'a ni niveau ni
      # quota à annoncer : il hérite du cadre du tournoi.
      fields << { type: "mrkdwn", text: "*Niveau*\n#{match.level.presence || 'Tout niveau'}" } unless match.tournament_linked?
      fields << { type: "mrkdwn", text: "*Format*\n#{match.format}" } if match.format.present?
      fields << { type: "mrkdwn", text: "*Joueurs*\n#{players_label(match)}" } unless match.tournament_linked?
      fields
    end

    # Section "inscrits", en bloc à part car la liste peut être longue. Renvoie un
    # tableau (splaté par l'appelant) pour n'ajouter AUCUN bloc sur une
    # confrontation, où les adversaires tiennent déjà dans les champs.
    def enrolled_block(match)
      return [] if match.tournament_confrontation?

      [{ type: "section", text: { type: "mrkdwn", text: enrolled_players_label(match) } }]
    end

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

      # Rencontre de tournoi : la composition est décidée par le tirage, personne
      # ne s'inscrit ni ne se désinscrit depuis Slack. On ne laisse donc que de la
      # consultation — le match, et le tableau du tournoi dont il fait partie.
      if match.tournament_linked?
        tournament_button = {
          type: "button",
          text: { type: "plain_text", text: "Voir le tournoi", emoji: true },
          url: tournament_url(match.tournament)
        }
        return [view_button, tournament_button]
      end

      return [view_button] unless match_status(match) == :upcoming

      join_button = {
        type: "button",
        style: "primary",
        text: { type: "plain_text", text: "S'inscrire au match", emoji: true },
        # action_id + value : lus par Slack::InteractivityController pour inscrire.
        action_id: "match_join",
        value: match.id.to_s
      }
      # La carte est partagée (pas par-utilisateur) : on affiche les deux boutons.
      # Un clic incohérent (déjà inscrit / pas inscrit) est géré côté job par un
      # message éphémère explicite, sans effet de bord.
      leave_button = {
        type: "button",
        style: "danger",
        text: { type: "plain_text", text: "Se désinscrire", emoji: true },
        action_id: "match_leave",
        value: match.id.to_s
      }
      # NB : pas de bouton « Annuler » ici. Une carte de channel est partagée
      # (mêmes blocs pour tous) → impossible de le réserver visuellement à
      # l'organisateur. L'annulation depuis Slack passe par la slash command
      # `/match-cancel`, dont la réponse éphémère n'est visible que de son auteur.
      [join_button, leave_button, view_button]
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
    #
    # Le score fait AUTORITÉ sur l'horloge : une rencontre dont le résultat est
    # saisi est finie, même si l'heure de fin annoncée n'est pas encore passée
    # (les joueurs saisissent souvent le score dans la foulée du dernier point).
    # À l'inverse, une carte « Terminé » d'après l'horloge mais sans score reste
    # exacte : la rencontre a bien eu lieu, on n'en connaît juste pas l'issue.
    def status_tag(match)
      outcome = confrontation_outcome(match)
      return outcome if outcome

      case match_status(match)
      when :in_progress then "🟢 *En cours*"
      when :completed   then "🏁 *Terminé*"
      else                   "🗓️ *À venir*"
      end
    end

    # "🏆 *Terminé* — victoire de Léa M." / "🤝 *Terminé* — match nul".
    # nil hors confrontation ou tant qu'aucun score n'est saisi : l'appelant
    # retombe alors sur le statut horaire.
    def confrontation_outcome(match)
      return nil unless match.tournament_confrontation?

      tmatch = match.tournament_match
      return nil if tmatch.nil? || !tmatch.score_entered?
      return "🤝 *Terminé* — match nul" if tmatch.draw?

      winner = tmatch.winner
      return "🏁 *Terminé*" if winner.nil?

      "🏆 *Terminé* — victoire de #{winner.short_name}"
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

    # Liste des joueurs affichée sur la carte, au format "Prénom N." — MÊME
    # périmètre que la grille "Joueurs inscrits" du site : deux groupes,
    # les "Inscrits" (approuvés + organisateur, organisateur en tête) et les
    # "En attente" (pending). Peu importe le canal : une inscription via Slack
    # crée un vrai match_user (compte lié obligatoire), donc web et Slack sont
    # couverts à l'identique. `includes(user: :profil)` évite le N+1 (short_name
    # lit le profil). Un bloc section Slack est plafonné à 3000 caractères → on
    # tronque l'ensemble par sécurité si la liste est très longue.
    # Le champ "qui joue ?" d'une confrontation. Il change de nature une fois la
    # rencontre jouée : tant qu'il n'y a pas de score c'est l'affiche
    # ("Léa M. 🆚 Tom R."), ensuite c'est le résultat ("Léa M. *2* – *0* Tom R.").
    # Un seul champ pour les deux : le score arrive là où l'œil cherchait déjà
    # les noms, et la carte ne grandit pas d'une ligne au moment du résultat.
    def opponents_label(match)
      names = match.confrontation_opponents.map(&:short_name)
      return "*Adversaires*\n_À déterminer_" if names.empty?

      # `names.size == 2` : un exempt (bye) n'a pas d'adversaire à opposer, et
      # aucun score n'a de sens en face d'un seul nom.
      tmatch = match.tournament_match
      unless tmatch&.score_entered? && names.size == 2
        return "*Adversaires*\n#{names.join(' 🆚 ')}"
      end

      a = tmatch.display_score_for(tmatch.player_a)
      b = tmatch.display_score_for(tmatch.player_b)
      "*Score*\n#{names.first} *#{a}* – *#{b}* #{names.last}"
    end

    def enrolled_players_label(match)
      players = match.displayed_match_users
                     .where("status IN (:shown) OR role = :organizer",
                            shown: %w[pending approved], organizer: "organisateur")
                     .includes(user: :profil)

      approved = players.select { |mu| mu.approved? || mu.role == "organisateur" }
                        .sort_by { |mu| mu.role == "organisateur" ? 0 : 1 }
      pending  = players.reject { |mu| mu.approved? || mu.role == "organisateur" }

      sections = [players_section("Inscrits", approved, empty: "Personne pour l'instant")]
      sections << players_section("En attente", pending) if pending.any?

      text = sections.join("\n\n")
      text.length > 2900 ? "#{text[0, 2900]}…" : text
    end

    # Une ligne "*Label (N)*\nPrénom N. · Prénom N.". Si vide et qu'un libellé de
    # repli est fourni, affiche "*Label*\n_repli_" ; sinon (groupe optionnel) rien.
    def players_section(label, match_users, empty: nil)
      names = match_users.map { |mu| mu.user.short_name }
      return "*#{label}*\n_#{empty}_" if names.empty?

      "*#{label} (#{names.size})*\n#{names.join(' · ')}"
    end
  end
end
