# Leçons — erreurs à ne pas répéter

> Après chaque correction de bug, ajouter ici une entrée courte : **symptôme → cause racine → correctif**.
> Objectif : ne pas répéter la même erreur deux fois.

<!-- Exemple de format :
## YYYY-MM-DD — Titre court du bug
- **Symptôme** : ce qui était cassé / observé
- **Cause racine** : la vraie cause (pas le symptôme)
- **Correctif** : ce qui a été changé, et fichier(s) concerné(s)
-->

## 2026-07-02 — Conversation qui disparaît parfois de la sidebar de chat
- **Symptôme** : une conversation (match/équipe/privée) disparaissait « parfois » de la sidebar du chat sticky et ne revenait qu'après un rechargement complet (F5).
- **Cause racine** : `Message#broadcast_unread_notifications` remontait la conv en tête via DEUX broadcasts ActionCable séparés (`broadcast_remove_to` puis `broadcast_prepend_to`). Si le rendu du partial du prepend échouait entre les deux, le `remove` était déjà parti → item supprimé. Comme `#sticky-chat-global` est `data-turbo-permanent`, la sidebar n'est jamais régénérée en navigation Turbo, d'où la persistance jusqu'au F5. Bug annexe : le broadcast match itérait TOUS les `match_users` (y compris pending/waiting/rejected), divergeant du filtre d'affichage `status='approved' OR role='organisateur'` → items fantômes.
- **Correctif** : nouveau partial `shared/_conversation_bump.turbo_stream.erb` qui groupe remove + prepend dans UN SEUL frame (rendu d'abord, diffusé ensuite → si le rendu échoue, rien n'est diffusé, l'item reste). `message.rb` refactorisé pour l'utiliser (`broadcast_conversation_bump`) et scope match aligné sur le filtre d'affichage.
- **Leçon** : ne jamais émettre remove + insertion d'un même élément en deux broadcasts distincts ; grouper dans un seul frame Turbo Stream. Garder la logique de broadcast alignée sur le filtre d'affichage de la vue.

## Niveaux absents à la création de match (mode multisport)
- **Symptôme** : le champ « Niveau requis » de `/matches/new` reste vide (aucun bouton), signalé en prod après la refonte du filtre multi-sport.
- **Cause racine** : `matches#new` faisait `@match.sport = current_sport`. En mode multisport (« Tous les sports »), `current_sport` renvoie `nil` → aucun sport présélectionné → au chargement, `match_form_controller#updateSport` tombe dans le `else` (guard `if (levelsMap[sportId])`) et ne génère ni boutons de niveau ni formats. La refonte du filtre (#342) a juste rendu le mode multisport bien plus facile à activer → le bug est devenu visible.
- **Correctif** : `@match.sport = current_sport || Sport.order(:name).first` (un match exige toujours un sport ; même fallback que le filtre de l'index `default_sport`).
- **Leçon** : quand un rendu JS dépend d'un champ présélectionné côté serveur, prévoir un fallback si la valeur peut être `nil`. Toujours reproduire avant de conclure : ici tout le code JS/data était correct, seul l'état « aucun sport actif » cassait le rendu.
- **Annexe** : les fixtures `matches.yml`/`teams.yml` n'avaient pas de `slug` (colonne NOT NULL + unique ajoutée par une migration récente) → toute la suite `matches_controller_test` plantait au chargement des fixtures. Les fixtures court-circuitent les callbacks du modèle qui génèrent le slug : renseigner un `slug` explicite.
