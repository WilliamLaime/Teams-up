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
