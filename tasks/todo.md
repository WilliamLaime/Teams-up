# PR 7 — Slash command `/match` + modale de création

## Objectif
Permettre à un utilisateur (au compte lié) de créer un match depuis Slack via `/match`,
qui ouvre une modale Block Kit. À la soumission : validation synchrone (erreurs inline),
création du match, puis post de la carte dans le channel d'origine.

## Étapes
- [ ] `MatchCreationService` : persiste un match construit, crée le match_user organisateur,
      planifie MatchReminderJob. Retourne un Result(match:, saved:). Réutilisable web + Slack.
- [ ] Refacto `MatchesController#create` pour déléguer le coeur (save + organisateur + reminder)
      au service, en gardant team/tournoi/mailer/webpush/slack autour. ISO-comportement.
- [ ] `Slack::MatchModalBuilder` : vue modale (sport, titre, date, heure, lieu, joueurs, niveau).
      callback_id "match_create", private_metadata = channel_id + response_url + team_id.
- [ ] `Slack::CommandsController#create` : `/match` → refus éphémère si non lié, sinon `views.open`.
- [ ] `InteractivityController` : gérer `view_submission` (callback "match_create") →
      valide (erreurs inline `response_action: errors`), crée via service, enqueue SlackNotifyJob.
- [ ] Route `post /slack/commands`.
- [ ] Tests : commands (signé, non lié, lié→views.open stub), view_submission (valide/invalide).
- [ ] `rails test` complet vert. Mettre à jour le plan.
