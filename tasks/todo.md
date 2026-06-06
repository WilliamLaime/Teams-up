---
name: Tests manquants — couverture complète de l'application
status: draft
created: 2026-05-29
---

## Objectif

Écrire tous les tests manquants de l'application Team Up pour couvrir les modèles, controllers et policies.
Les fichiers de tests déjà existants (`match_test.rb`, `profil_test.rb`, `user_test.rb`, etc.) sont tous vides (squelettes sans assertions). Tout est donc à écrire.

## Fichiers impactés

### Modèles (à créer ou compléter)
- `test/models/user_test.rb`
- `test/models/match_test.rb`
- `test/models/profil_test.rb`
- `test/models/match_user_test.rb`
- `test/models/notification_test.rb`
- `test/models/team_test.rb`
- `test/models/friendship_test.rb`
- `test/models/avis_test.rb`
- `test/models/match_vote_test.rb`
- `test/models/team_invitation_test.rb`
- `test/models/team_member_test.rb`
- `test/models/sport_test.rb`
- `test/models/venue_test.rb`
- `test/models/message_test.rb`
- `test/models/contact_message_test.rb`
- `test/models/waitlist_entry_test.rb`
- `test/models/sport_profil_test.rb`

### Controllers (à créer)
- `test/controllers/matches_controller_test.rb`
- `test/controllers/teams_controller_test.rb`
- `test/controllers/match_users_controller_test.rb`
- `test/controllers/profils_controller_test.rb`
- `test/controllers/friendships_controller_test.rb`
- `test/controllers/notifications_controller_test.rb`
- `test/controllers/avis_controller_test.rb`
- `test/controllers/match_votes_controller_test.rb`
- `test/controllers/team_invitations_controller_test.rb`
- `test/controllers/team_members_controller_test.rb`
- `test/controllers/contact_messages_controller_test.rb`

### Policies (à créer)
- `test/policies/team_policy_test.rb`
- `test/policies/avis_policy_test.rb`
- `test/policies/friendship_policy_test.rb`
- `test/policies/match_user_policy_test.rb`
- `test/policies/profil_policy_test.rb`
- `test/policies/notification_policy_test.rb`
- `test/policies/team_invitation_policy_test.rb`
- `test/policies/team_member_policy_test.rb`
- `test/policies/match_vote_policy_test.rb`

---

## Étapes

### Modèles

- [ ] `test/models/user_test.rb` — validations : password doit contenir majuscule + chiffre + symbole ; password trop simple rejeté ; first_name et last_name obligatoires à la création (on: :create) ; genre doit être dans GENRES ou nil ; méthodes : `friends_with?` retourne vrai si friendship accepted dans un sens OU l'autre ; `all_friends` retourne les deux sens ; `pending_request_sent_to?` retourne vrai si friendship pending ; `pending_request_from?` retourne vrai si inverse pending ; `display_name` retourne "Prénom Nom" si profil présent, sinon email ; `rank` retourne "bronze" pour level 1-2, "silver" 3-4, "gold" 5-6, "platinum" 7-8, "emerald" 9+

- [ ] `test/models/match_test.rb` — validations : level obligatoire ; player_left obligatoire, entier, >= 1 ; players_present obligatoire si format == "Libre" ; match doit être au minimum 30 min dans le futur (sinon erreur :base) ; level doit être valide pour le sport sélectionné (hors "Tout niveau") ; scopes : `upcoming` exclut les matchs passés ; `publicly_visible` exclut les matchs visibility == "private" ; `completed` retourne les matchs terminés (> 1h) ; `active_for_user` retourne les matchs pas encore terminés ; `visible_for_genre` avec user femme retourne tous les matchs, avec user non-femme exclut les matchs "feminin" ; méthodes : `private?` retourne vrai si visibility == "private" ; `public?` retourne vrai si visibility == "public" ou nil ; `full?` retourne vrai si player_left <= 0 ; `urgent?` retourne vrai si le match a lieu dans moins de 2h ; `past?` retourne vrai si déjà passé ; `in_progress?` retourne vrai si débuté mais < 1h ; `completed?` retourne vrai si > 1h après le début ; callback : `generate_private_token` est appelé avant la création d'un match privé et génère un token unique

- [ ] `test/models/profil_test.rb` — validations : first_name obligatoire ; last_name obligatoire ; preferred_city max 100 caractères ; méthodes XP : `xp_for_next_level` retourne le bon seuil selon le niveau ; `xp_for_current_level` retourne le plancher du niveau actuel ; `xp_progress_percent` retourne 0 à 100 correctement ; `recalculate_level!` met à jour xp_level et attribue 3 stat_points par niveau gagné ; `level_badge_color` retourne "success" niveaux 1-4, "primary" 5-8, "warning" 9-10 ; `card_tier_class` retourne la bonne classe CSS selon le niveau ; `theme` retourne "light" si light_mode? est vrai, sinon "dark" ; `needs_onboarding_modal?` retourne vrai si onboarding_shown_at est nil ; `needs_profile_reminder?` retourne faux si preferred_city présente, faux si onboarding < 7 jours, vrai si toutes conditions remplies

- [ ] `test/models/match_user_test.rb` — validations : role doit être dans ROLES (liste à identifier) ; status doit être dans STATUSES ; user_id unique par match_id ; méthodes : `approved?` retourne vrai si status == "approved" ; `pending?` retourne vrai si status == "pending" (vérifier les méthodes d'instance existantes)

- [ ] `test/models/notification_test.rb` — associations : appartient à user ; appartient à actor (optionnel) ; scopes : `unread` retourne uniquement les notifications non lues ; `recent` retourne du plus récent au plus ancien

- [ ] `test/models/team_test.rb` — validations : name obligatoire ; name max 50 caractères ; name unique par captain_id (deux équipes du même nom pour le même captain rejetées) ; méthodes : `captain?` retourne vrai si l'user est le captain ; `member?` retourne vrai si l'user est dans les members ; `invitation_pending_for?` retourne vrai si une invitation pending existe pour cet user ; `members_count` retourne le bon nombre ; callback `add_captain_as_member` : le captain est automatiquement ajouté comme TeamMember avec role "captain" après création ; `sanitize_badge_svg` : supprime les balises `<script>` et les handlers "onload=" du SVG avant sauvegarde ; `badge_display` retourne :image si badge_image attaché, :svg si badge_svg présent, nil sinon

- [ ] `test/models/friendship_test.rb` — validations : status doit être dans STATUSES (pending/accepted/declined) ; friend_id obligatoire ; validation `cannot_friend_yourself` rejette si friend_id == user_id ; scopes : `pending` retourne les friendships en attente ; `accepted` retourne les friendships acceptées ; `declined` retourne les friendships refusées ; méthodes : `pending?`, `accepted?`, `declined?` retournent le bon booléen

- [ ] `test/models/avis_test.rb` — validations : rating obligatoire, doit être entre 1 et 5 ; unicité reviewer_id par couple reviewed_user_id + match_id ; `cannot_review_yourself` rejette si reviewer == reviewed_user ; `both_players_must_have_played` rejette si le reviewer n'est pas "approved" dans ce match ; `both_players_must_have_played` rejette si le reviewed_user n'est pas "approved" dans ce match ; `within_review_window` rejette si le match n'est pas encore terminé ; `within_review_window` rejette si > 7 jours après la fin du match ; scopes : `mutual` retourne les avis avec mutual == true ; `non_mutual` retourne les avis avec mutual == false ; callback `set_mutual_flag` : quand A→B est créé et B→A existe, les deux passent mutual: true ; callback `clear_mutual_flag` : quand A→B est détruit, B→A repasse mutual: false ; callback `recalculate_average` : recalcule average_rating et avis_count sur le profil noté

- [ ] `test/models/match_vote_test.rb` — validations : unicité voter_id par match_id (un seul vote par match) ; `cannot_vote_for_yourself` rejette si voter == voted_for ; `both_players_must_have_played` rejette si voter n'est pas "approved" dans ce match ; `both_players_must_have_played` rejette si voted_for n'est pas "approved" dans ce match ; `within_vote_window` rejette si match pas encore terminé ; `within_vote_window` rejette si > 7 jours après la fin ; callback `recalculate_homme_du_match` : met à jour homme_du_match_id sur le match après création d'un vote ; `recalculate_homme_du_match` met à jour homme_du_match_count sur le profil gagnant/perdant

- [ ] `test/models/team_invitation_test.rb` — validations : status doit être dans STATUSES (pending/accepted/refused/proposed) ; unicité invitee_id par team_id pour status "pending" ; unicité invitee_id par team_id pour status "proposed" ; méthodes : `pending?`, `accepted?`, `refused?`, `proposed?` retournent le bon booléen ; scopes : `pending`, `accepted`, `refused`, `proposed` filtrent correctement

- [ ] `test/models/team_member_test.rb` — validations : role doit être dans ROLES (captain/member) ; unicité user_id par team_id (un user ne peut pas être deux fois membre de la même équipe) ; méthodes : `captain?` retourne vrai si role == "captain" ; `member?` retourne vrai si role == "member"

- [ ] `test/models/sport_test.rb` — validations : name obligatoire et unique ; slug obligatoire et unique ; icon obligatoire ; méthodes : `available_formats` retourne les bons formats selon le slug (ex: football → 5v5, 11v11, Libre) ; `available_levels` retourne les bons niveaux selon le slug (ex: tennis → 6 niveaux FFT) ; `default_player_count` retourne le players du premier format ; `max_player_count` retourne le max des formats (hors nil)

- [ ] `test/models/venue_test.rb` — validations : name obligatoire ; city obligatoire ; scopes : `in_city` retourne les venues dont city contient la valeur (ILIKE) ; `by_sport` retourne les venues dont sport_type contient la valeur (ILIKE)

- [ ] `test/models/message_test.rb` — validations : content obligatoire ; content max 1000 caractères ; `belongs_to_match_or_private_conversation_or_team` rejette si match_id ET private_conversation_id ET team_id sont tous nil

- [ ] `test/models/contact_message_test.rb` — validations : prenom obligatoire ; nom obligatoire ; email obligatoire ; sujet obligatoire ; message obligatoire ; `email_valide_et_existant` rejette un format d'email invalide (ex: "pas-un-email") ; scopes : `unread` retourne les messages avec lu: false ; `recent` trie du plus récent au plus ancien

- [ ] `test/models/waitlist_entry_test.rb` — validations : email obligatoire ; unicité de l'email (case-insensitive) ; format email valide via URI::MailTo ; callback before_validation : email est normalisé en minuscules et strip

- [ ] `test/models/sport_profil_test.rb` — validation `level_valid_for_sport` : rejette un niveau qui n'appartient pas à la grille du sport (ex: "Expert" pour un sport sans ce niveau) ; accepte un niveau vide (level est optionnel) ; accepte un niveau valide pour le sport

---

### Controllers

- [ ] `test/controllers/matches_controller_test.rb`
  - `GET /matches` (index) : retourne 200 pour un visiteur non connecté ; retourne 200 pour un user connecté ; avec `?mine=1` retourne uniquement les matchs de l'user connecté ; avec `?mine=1&status=completed` retourne uniquement les matchs terminés de l'user
  - `GET /matches/:id` (show) : retourne 200 pour un match public ; redirige vers root pour un match privé sans token ; retourne 200 pour un match privé avec le bon token ; retourne 200 pour l'organisateur d'un match privé
  - `GET /matches/new` : redirige vers login si non connecté ; retourne 200 si connecté
  - `POST /matches` (create) : redirige vers login si non connecté ; crée le match et redirige si params valides ; réaffiche le formulaire (422) si params invalides ; ne permet pas à un non-femme de créer un match "feminin"
  - `GET /matches/:id/edit` : redirige vers login si non connecté ; retourne 200 pour l'organisateur ; lève Pundit::NotAuthorizedError pour un autre user
  - `PATCH /matches/:id` (update) : met à jour et redirige si organisateur et params valides ; réaffiche le formulaire (422) si params invalides ; lève Pundit::NotAuthorizedError pour un non-organisateur
  - `DELETE /matches/:id` (destroy) : détruit le match et redirige si organisateur ; lève Pundit::NotAuthorizedError pour un non-organisateur
  - `PATCH /matches/:id/make_public` : passe le match en public et redirige si organisateur ; lève Pundit::NotAuthorizedError pour un non-organisateur

- [ ] `test/controllers/teams_controller_test.rb`
  - `GET /teams` (index) : redirige vers login si non connecté ; retourne 200 si connecté ; retourne uniquement les équipes de l'user
  - `GET /teams/:id` (show) : redirige vers login si non connecté ; retourne 200 pour un membre ; lève Pundit::NotAuthorizedError pour un non-membre
  - `GET /teams/new` : redirige vers login si non connecté ; retourne 200 si connecté
  - `POST /teams` (create) : crée l'équipe et ajoute le captain comme membre ; réaffiche le formulaire (422) si params invalides
  - `PATCH /teams/:id` (update) : met à jour et redirige si captain ; lève Pundit::NotAuthorizedError pour un non-captain
  - `DELETE /teams/:id` (destroy) : détruit l'équipe et redirige si captain ; lève Pundit::NotAuthorizedError pour un non-captain
  - `PATCH /teams/:id/transfer_captain` : transfère le capitanat si captain ; redirige avec alert si new_captain n'est pas membre ; lève Pundit::NotAuthorizedError pour un non-captain
  - `DELETE /teams/:id/leave` : supprime le TeamMember de l'user ; lève Pundit::NotAuthorizedError pour le captain

- [ ] `test/controllers/match_users_controller_test.rb`
  - `POST /matches/:match_id/match_users` (create) : redirige vers login si non connecté ; crée l'inscription approved si match en mode automatique et place disponible ; crée l'inscription pending si mode validation manuelle ; crée l'inscription waiting si match complet ; redirige avec alert si user déjà inscrit ; redirige avec alert si match "feminin" et user non-femme
  - `DELETE /matches/:match_id/match_users/:id` (destroy) : supprime l'inscription si propriétaire ; lève Pundit::NotAuthorizedError pour un autre user ; promeut le suivant en file d'attente si was_approved
  - `PATCH /matches/:match_id/match_users/:id/approve` : approuve le joueur si organisateur ; lève Pundit::NotAuthorizedError pour un non-organisateur ; redirige vers le match si joueur déjà traité (idempotence)
  - `PATCH /matches/:match_id/match_users/:id/reject` : rejette le joueur si organisateur ; lève Pundit::NotAuthorizedError pour un non-organisateur
  - `PATCH /matches/:match_id/match_users/:id/confirm` : confirme la participation si c'est l'user concerné ; redirige avec alert si match non-équipe

- [ ] `test/controllers/profils_controller_test.rb`
  - `GET /profil` (show_simple) : redirige vers login si non connecté ; retourne 200 pour l'user connecté
  - `GET /users/:id/profil` (show_user_simple) : retourne 200 pour un visiteur non connecté ; retourne 200 pour l'user lui-même ; retourne 200 pour un autre user connecté
  - `GET /profil/edit` : redirige vers login si non connecté ; retourne 200 pour l'user connecté ; lève Pundit::NotAuthorizedError si on essaie d'accéder au profil d'un autre
  - `PATCH /profil` (update) : met à jour et redirige si params valides ; réaffiche le formulaire (422) si params invalides
  - `POST /profil/dismiss_onboarding` : met à jour onboarding_shown_at ; redirige vers root_path par défaut ; redirige vers le chemin local fourni dans params[:redirect_to] ; ignore les redirections vers des domaines externes
  - `DELETE /profil/dismiss_reminder` : met à jour profile_reminder_dismissed_at ; répond en Turbo Stream
  - `PATCH /profil/update_theme` : bascule light_mode et répond JSON avec le nouveau thème

- [ ] `test/controllers/friendships_controller_test.rb`
  - `POST /users/:user_id/friendship` (create) : redirige vers login si non connecté ; crée la friendship pending ; redirige avec alert si on essaie de s'ajouter soi-même ; redirige avec alert si déjà amis ; redirige avec alert si demande déjà en attente
  - `PATCH /users/:user_id/friendship/accept` : accepte la friendship et passe en "accepted" ; redirige avec alert si aucune demande en attente de cet user ; lève Pundit::NotAuthorizedError si l'user connecté n'est pas le destinataire
  - `PATCH /users/:user_id/friendship/decline` : détruit la friendship ; redirige avec alert si aucune demande en attente
  - `DELETE /users/:user_id/friendship` (destroy) : détruit la friendship initiée par current_user ; détruit une friendship accepted initiée par l'autre ; redirige avec alert si aucune relation

- [ ] `test/controllers/notifications_controller_test.rb`
  - `GET /notifications` (index) : redirige vers login si non connecté ; retourne 200 et uniquement les notifications de l'user connecté
  - `PATCH /notifications/:id/mark_read` : passe la notification en read: true et redirige vers son lien ; lève Pundit::NotAuthorizedError si la notification n'appartient pas à l'user connecté
  - `DELETE /notifications/:id` (destroy) : détruit la notification ; répond 200 JSON si format JSON ; lève Pundit::NotAuthorizedError si la notification n'appartient pas à l'user connecté
  - `PATCH /notifications/mark_all_read` : passe toutes les notifs unread de l'user en read: true

- [ ] `test/controllers/avis_controller_test.rb`
  - `POST /users/:user_id/avis` (create) : redirige vers login si non connecté ; crée l'avis et redirige si params valides et match éligible ; répond JSON avec success: true si format JSON et save ok ; répond JSON avec error et 422 si modèle invalide ; redirige avec alert si modèle invalide (format HTML) ; lève Pundit::NotAuthorizedError si l'user essaie de se noter lui-même

- [ ] `test/controllers/match_votes_controller_test.rb`
  - `POST /matches/:match_id/match_votes` (create) : redirige vers login si non connecté ; crée le vote et redirige si params valides ; répond JSON success si format JSON ; répond JSON error 422 si modèle invalide (déjà voté, voter pour soi, hors fenêtre) ; lève Pundit::NotAuthorizedError si user vote pour lui-même

- [ ] `test/controllers/team_invitations_controller_test.rb`
  - `POST /teams/:team_id/team_invitations` (create) : redirige vers login si non connecté ; crée l'invitation et redirige si captain et invitee valide ; redirige avec alert si invitee introuvable ; redirige avec alert si invitee déjà membre ; lève Pundit::NotAuthorizedError si non-captain
  - `PATCH /teams/:team_id/team_invitations/:id` (update) avec status=accepted : crée le TeamMember et accepte l'invitation si c'est l'invitee ; lève Pundit::NotAuthorizedError si non-invitee
  - `PATCH /teams/:team_id/team_invitations/:id` (update) avec status=refused : passe l'invitation en "refused" ; lève Pundit::NotAuthorizedError si non-invitee
  - `DELETE /teams/:team_id/team_invitations/:id` (destroy) : détruit l'invitation si captain ; lève Pundit::NotAuthorizedError si non-captain
  - `POST /teams/:team_id/team_invitations/propose` : crée une invitation status="proposed" si membre non-captain ; redirige avec alert si captain essaie de proposer ; redirige avec alert si invitee introuvable

- [ ] `test/controllers/team_members_controller_test.rb`
  - `DELETE /teams/:team_id/team_members/:id` (destroy) : redirige vers login si non connecté ; retire le membre et redirige si captain ; lève Pundit::NotAuthorizedError si non-captain ; lève Pundit::NotAuthorizedError si le captain essaie de se retirer lui-même

- [ ] `test/controllers/contact_messages_controller_test.rb`
  - `POST /contact` (create) : crée le message et redirige si tous les champs valides ; réaffiche "pages/contact" (422) si champs manquants ; accessible sans être connecté (skip_before_action)

---

### Policies

- [ ] `test/policies/team_policy_test.rb`
  - `index?` : retourne vrai pour tout user connecté
  - `show?` : retourne vrai pour tout user connecté
  - `create?` : retourne vrai pour tout user connecté
  - `update?` : retourne vrai si l'user est le captain ; retourne faux si l'user est membre mais pas captain
  - `destroy?` : retourne vrai si captain ; retourne faux sinon
  - `transfer_captain?` : retourne vrai si captain ; retourne faux sinon
  - `leave?` : retourne vrai si l'user est membre ET pas captain ; retourne faux si l'user est captain ; retourne faux si l'user n'est pas membre
  - `Scope#resolve` : retourne les équipes dont l'user est membre ; retourne une collection vide si user non connecté

- [ ] `test/policies/avis_policy_test.rb`
  - `create?` : retourne faux si user nil (non connecté) ; retourne faux si user == reviewed_user (se noter soi-même) ; retourne vrai si user connecté et reviewed_user différent

- [ ] `test/policies/friendship_policy_test.rb`
  - `create?` : retourne vrai si user connecté ; retourne faux si user nil
  - `destroy?` : retourne vrai si l'user est l'initiateur de la friendship (record.user == user) ; retourne vrai si l'user est le destinataire ET la friendship est accepted ; retourne faux si l'user est le destinataire ET la friendship est pending
  - `accept?` : retourne vrai si l'user est le destinataire (record.friend == user) ; retourne faux si l'user est l'initiateur
  - `decline?` : retourne vrai si l'user est le destinataire ; retourne faux si l'user est l'initiateur

- [ ] `test/policies/match_user_policy_test.rb`
  - `create?` : retourne vrai pour tout user connecté
  - `destroy?` : retourne vrai si record.user == user ; retourne faux si c'est un autre user
  - `approve?` : retourne vrai si l'user est l'organisateur du match (role "organisateur" dans match_users) ; retourne faux pour un joueur lambda
  - `reject?` : même logique que approve?
  - `confirm?` : retourne vrai si record.user == user ; retourne faux pour un autre user

- [ ] `test/policies/profil_policy_test.rb`
  - `show?` : retourne vrai si l'user est le propriétaire du profil (record.user == user) ; retourne faux pour un autre user
  - `update?` : retourne vrai si propriétaire ; retourne faux pour un autre user

- [ ] `test/policies/notification_policy_test.rb`
  - `mark_read?` : retourne vrai si la notification appartient à l'user (record.user == user) ; retourne faux sinon
  - `destroy?` : retourne vrai si appartient à l'user ; retourne faux sinon
  - `mark_all_read?` : retourne vrai pour tout user connecté
  - `Scope#resolve` : retourne uniquement les notifications de l'user connecté

- [ ] `test/policies/team_invitation_policy_test.rb`
  - `create?` : retourne vrai si l'user est le captain de l'équipe ; retourne faux pour un membre non-captain
  - `update?` : retourne vrai si l'user est l'invitee (record.invitee_id == user.id) ; retourne faux pour le captain
  - `destroy?` : retourne vrai si captain ; retourne faux pour l'invitee

- [ ] `test/policies/team_member_policy_test.rb`
  - `destroy?` : retourne vrai si l'user est le captain ET que le membre à retirer est différent de l'user ; retourne faux si l'user essaie de se retirer lui-même ; retourne faux si l'user est membre mais pas captain

- [ ] `test/policies/match_vote_policy_test.rb`
  - `create?` : retourne vrai si user connecté et voted_for != user ; retourne faux si user nil ; retourne faux si user == voted_for
