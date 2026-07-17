# Audit + montée en charge (30-50 users) — Plan

Contexte : audit complet réalisé (3 agents). Site fonctionnellement sain, aucun bug critique.
Décisions user : URLs = slug lisible + suffixe court ; implémenter perf + sécu/qualité + URLs ; + bug chat "conversation disparaît".

## Phase 0 — Bug chat "conversation disparaît" (prioritaire)
- [ ] Identifier la cause racine (agent d'investigation lancé)
- [ ] Corriger le mécanisme qui retire une conversation à tort
- [ ] Vérifier non-régression
- [ ] Noter l'apprentissage dans tasks/lessons.md

## Phase 1 — Perf / scalabilité (ROI le plus élevé)
- [ ] N+1 chat sticky : précalculer derniers messages + non-lus (GROUP BY), passer en locals
- [ ] N+1 cartes de match : précharger users:profil + blobs avatars (matches#index, pages#home)
- [ ] Pagination Pagy : matches#index, teams#index
- [ ] Index DB : notifications(user_id,read,created_at), messages(*_id,created_at), match_users(user_id,status)
- [ ] Bullet en group :development
- [ ] Vérifier via logs SQL que les N+1 ont disparu

## Phase 2 — Sécurité / qualité
- [ ] MessagePolicy / PrivateConversationPolicy
- [ ] sanitize articles/show.html.erb:101
- [ ] Durcir data: URLs dans team.rb (badges SVG)
- [ ] return après redirect messages_controller.rb:200

## Phase 3 — URLs sans ID (slug lisible + suffixe)
- [ ] Colonne slug + migration + backfill sur matches & teams
- [ ] Génération slug (title/name + suffixe court unique) + to_param
- [ ] Adapter ~10 controllers (find_by!(slug:))
- [ ] Router param: :slug
- [ ] Vérifier cibles Turbo (garder id numérique côté DOM)
- [ ] Articuler avec private_token
- [ ] Régénérer sitemap + json_ld

## Fait (branche feat/audit-slugs-perf-chat)
- [x] Phase 0 — bug chat corrigé (broadcast atomique) + vérifié broadcasts match/team/privé
- [x] Phase 1 — N+1 chat sticky, N+1 cartes match, index DB, Bullet (pagination = suivi)
- [x] Phase 2 — sanitize articles, return manquant (policies = suivi, refactor sans faille)
- [x] Phase 3 — slugs matchs/équipes (concern Sluggable, rétro-compat id), 11 controllers
- [x] Extra — avatars chat + organisateurs cliquables ; tâche rake chat:demo

## Suivi recommandé (non fait, à décider)
- [ ] Pagination Pagy matches#index / teams#index (AVEC nav dans les vues)
- [ ] MessagePolicy / PrivateConversationPolicy (centralisation autz)
- [ ] Régénérer le sitemap en prod (rake sitemap:refresh) après déploiement

## Vérif finale
- [ ] rails test (fixtures à vérifier)
- [ ] Parcours manuel des flux clés en local
