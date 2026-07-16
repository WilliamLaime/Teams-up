# Feature : statut live du match dans la carte Slack

## Objectif
Afficher un tag de statut sur la carte Slack et le mettre à jour en direct :
- **À venir** (now < début) : carte normale + bouton « S'inscrire au match »
- **🟢 En cours** (début ≤ now < fin) : tag, plus de bouton d'inscription
- **🏁 Terminé** (now ≥ fin) : tag, plus de bouton d'inscription

Mise à jour en direct via `chat.update` (le message posté est ré-édité aux
transitions début puis fin). On retire le skip « match passé » du job.

## Étapes
1. [x] Migration + modèle `SlackMatchMessage` (match, workspace, channel_id, message_ts)
2. [x] `SlackNotifierService#update_message` (chat.update) ; `post_message` renvoie déjà ts/channel
3. [x] `BlockKitBuilder` : tag de statut + bouton S'inscrire seulement si À venir
4. [x] `SlackNotifyJob` : retirer le skip, persister le message posté, planifier MAJ (début + fin)
5. [x] `SlackMatchStatusJob` : ré-édite toutes les cartes stockées du match au statut courant
6. [x] Vérifs syntaxe + runner + tests (slack 15✓, match 41✓)

## Limite connue (v1)
Si l'organisateur modifie la date/heure APRÈS création, les MAJ planifiées
gardent les anciens horaires (pas de reprogrammation). À noter dans lessons.
