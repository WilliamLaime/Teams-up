require "test_helper"

# Tests du modèle Avis.
# Un Avis représente la note qu'un joueur laisse à un coéquipier après un match.
# Règles :
#   - La note doit être entre 1 et 5
#   - Un reviewer ne peut noter la même personne qu'une fois par match
#   - On ne peut pas se noter soi-même
#   - Les deux joueurs doivent avoir participé au match (status: "approved")
#   - Le match doit être terminé ET dans la fenêtre de 7 jours
#   - Callback set_mutual_flag : si A note B et que B a déjà noté A → les deux deviennent "mutual"
#   - Callback recalculate_average : met à jour le profil noté
class AvisTest < ActiveSupport::TestCase
  teardown { teardown_db }

  # Crée un match terminé il y a 2 heures (dans la fenêtre des 7j).
  # On utilise save(validate: false) car le modèle Match interdit la création
  # d'un match dans le passé (validates :match_must_be_at_least_30min_in_future).
  # Ici on veut tester les avis, pas la validation du match lui-même.
  def create_completed_match(user:)
    sport = Sport.create!(name: "Football Avis", slug: "football_avis_test", icon: "⚽")
    # Construit l'objet sans sauvegarder
    match = Match.new(
      title:       "Match Terminé",
      place:       "Terrain",
      date:        2.hours.ago.to_date,
      time:        2.hours.ago,
      player_left: 10,
      level:       "Tout niveau", # champ obligatoire
      user:        user,
      sport:       sport
    )
    # Bypass la validation de date (on teste les avis, pas la création de match)
    match.save(validate: false)
    match
  end

  # Crée un match dont l'heure de fin est hors fenêtre (il y a 8 jours).
  # Même approche : save(validate: false) pour bypasser la contrainte de date.
  def create_old_completed_match(user:)
    sport = Sport.create!(name: "Football Old", slug: "football_old_test", icon: "⚽")
    match = Match.new(
      title:       "Vieux Match",
      place:       "Terrain",
      date:        8.days.ago.to_date,
      time:        8.days.ago,
      player_left: 10,
      level:       "Tout niveau", # champ obligatoire
      user:        user,
      sport:       sport
    )
    match.save(validate: false)
    match
  end

  # Ajoute deux utilisateurs comme participants approuvés à un match
  def add_approved_players(match:, reviewer:, reviewed:)
    MatchUser.create!(user: reviewer, match: match, status: "approved", role: "joueur")
    MatchUser.create!(user: reviewed, match: match, status: "approved", role: "joueur")
  end

  # ════════════════════════════════════════════════════════════════════════════
  # VALIDATIONS — rating
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : une note de 3 est valide
  def test_avis_valide_avec_rating_3
    reviewer = create_test_user(email: "rev1@example.com", first_name: "Rev", last_name: "Un")
    reviewed = create_test_user(email: "rev2@example.com", first_name: "Rev", last_name: "Deux")
    match    = create_completed_match(user: reviewer)
    add_approved_players(match: match, reviewer: reviewer, reviewed: reviewed)

    avis = Avis.new(reviewer: reviewer, reviewed_user: reviewed, match: match, rating: 3)
    assert avis.valid?, "Une note de 3 doit être valide : #{avis.errors.full_messages}"
  end

  # Cas d'erreur : une note de 0 est invalide (en dessous de 1)
  def test_avis_invalide_avec_rating_0
    reviewer = create_test_user(email: "rev3@example.com", first_name: "Rev", last_name: "Trois")
    reviewed = create_test_user(email: "rev4@example.com", first_name: "Rev", last_name: "Quatre")
    match    = create_completed_match(user: reviewer)
    add_approved_players(match: match, reviewer: reviewer, reviewed: reviewed)

    avis = Avis.new(reviewer: reviewer, reviewed_user: reviewed, match: match, rating: 0)
    refute avis.valid?, "Une note de 0 doit être invalide (minimum 1)"
    assert avis.errors[:rating].any?, "Une erreur sur :rating doit être présente"
  end

  # Cas d'erreur : une note de 6 est invalide (au-dessus de 5)
  def test_avis_invalide_avec_rating_6
    reviewer = create_test_user(email: "rev5@example.com", first_name: "Rev", last_name: "Cinq")
    reviewed = create_test_user(email: "rev6@example.com", first_name: "Rev", last_name: "Six")
    match    = create_completed_match(user: reviewer)
    add_approved_players(match: match, reviewer: reviewer, reviewed: reviewed)

    avis = Avis.new(reviewer: reviewer, reviewed_user: reviewed, match: match, rating: 6)
    refute avis.valid?, "Une note de 6 doit être invalide (maximum 5)"
  end

  # Edge case : les notes aux limites (1 et 5) sont valides
  def test_avis_valide_avec_rating_1_et_5
    reviewer = create_test_user(email: "rev7@example.com", first_name: "Rev", last_name: "Sept")
    reviewed = create_test_user(email: "rev8@example.com", first_name: "Rev", last_name: "Huit")
    match    = create_completed_match(user: reviewer)
    add_approved_players(match: match, reviewer: reviewer, reviewed: reviewed)

    [1, 5].each do |note|
      avis = Avis.new(reviewer: reviewer, reviewed_user: reviewed, match: match, rating: note)
      assert avis.valid?, "La note #{note} doit être valide (limite)"
    end
  end

  # ════════════════════════════════════════════════════════════════════════════
  # VALIDATION — cannot_review_yourself
  # ════════════════════════════════════════════════════════════════════════════

  # Cas d'erreur : on ne peut pas se noter soi-même
  def test_cannot_review_yourself
    user  = create_test_user(email: "self_rev@example.com", first_name: "Self", last_name: "Rev")
    match = create_completed_match(user: user)
    MatchUser.create!(user: user, match: match, status: "approved", role: "joueur")

    avis = Avis.new(reviewer: user, reviewed_user: user, match: match, rating: 5)
    refute avis.valid?, "On ne peut pas se noter soi-même"
    assert avis.errors[:base].any? { |e| e.include?("vous-même") },
           "L'erreur doit mentionner l'interdiction de se noter soi-même"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # VALIDATION — unicité reviewer/reviewed/match
  # ════════════════════════════════════════════════════════════════════════════

  # Cas d'erreur : un reviewer ne peut noter la même personne qu'une fois par match
  def test_unicite_reviewer_reviewed_match
    reviewer = create_test_user(email: "uni_rev@example.com", first_name: "Uni", last_name: "Rev")
    reviewed = create_test_user(email: "uni_rev2@example.com", first_name: "Uni", last_name: "Reviewed")
    match    = create_completed_match(user: reviewer)
    add_approved_players(match: match, reviewer: reviewer, reviewed: reviewed)

    # Crée un premier avis
    Avis.create!(reviewer: reviewer, reviewed_user: reviewed, match: match, rating: 4)
    # Essaie d'en créer un deuxième → doit être invalide
    doublon = Avis.new(reviewer: reviewer, reviewed_user: reviewed, match: match, rating: 3)
    refute doublon.valid?, "On ne peut pas noter la même personne deux fois dans le même match"
    assert doublon.errors[:reviewer_id].any?, "Une erreur d'unicité sur :reviewer_id doit être présente"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # VALIDATION — both_players_must_have_played
  # ════════════════════════════════════════════════════════════════════════════

  # Cas d'erreur : le reviewer n'a pas participé au match
  def test_reviewer_doit_avoir_joue
    reviewer = create_test_user(email: "play_rev@example.com", first_name: "Play", last_name: "Rev")
    reviewed = create_test_user(email: "play_rev2@example.com", first_name: "Play", last_name: "Reviewed")
    match    = create_completed_match(user: reviewer)
    # Seul reviewed est inscrit (approved) → reviewer n'a pas joué
    MatchUser.create!(user: reviewed, match: match, status: "approved", role: "joueur")

    avis = Avis.new(reviewer: reviewer, reviewed_user: reviewed, match: match, rating: 4)
    refute avis.valid?, "On ne peut pas laisser un avis si on n'a pas participé au match"
    assert avis.errors[:base].any? { |e| e.include?("participé") },
           "L'erreur doit mentionner l'obligation d'avoir participé"
  end

  # Cas d'erreur : le joueur noté n'a pas participé au match
  def test_reviewed_doit_avoir_joue
    reviewer = create_test_user(email: "play_rev3@example.com", first_name: "Play3", last_name: "Rev")
    reviewed = create_test_user(email: "play_rev4@example.com", first_name: "Play4", last_name: "Reviewed")
    match    = create_completed_match(user: reviewer)
    # Seul reviewer est inscrit (approved) → reviewed n'a pas joué
    MatchUser.create!(user: reviewer, match: match, status: "approved", role: "joueur")

    avis = Avis.new(reviewer: reviewer, reviewed_user: reviewed, match: match, rating: 4)
    refute avis.valid?, "On ne peut pas noter quelqu'un qui n'a pas participé au match"
    assert avis.errors[:base].any? { |e| e.include?("participé") }
  end

  # ════════════════════════════════════════════════════════════════════════════
  # VALIDATION — within_review_window
  # ════════════════════════════════════════════════════════════════════════════

  # Cas d'erreur : un match trop ancien (>7j) ne permet plus de noter
  def test_avis_invalide_si_match_trop_ancien
    reviewer = create_test_user(email: "old_rev@example.com", first_name: "Old", last_name: "Rev")
    reviewed = create_test_user(email: "old_rev2@example.com", first_name: "Old", last_name: "Reviewed")
    match    = create_old_completed_match(user: reviewer)
    add_approved_players(match: match, reviewer: reviewer, reviewed: reviewed)

    avis = Avis.new(reviewer: reviewer, reviewed_user: reviewed, match: match, rating: 4)
    refute avis.valid?, "On ne peut pas noter un match terminé il y a plus de 7 jours"
    assert avis.errors[:base].any? { |e| e.include?("7 jours") },
           "L'erreur doit mentionner la fenêtre de 7 jours"
  end

  # Cas d'erreur : un match futur (non terminé) ne permet pas de noter
  def test_avis_invalide_si_match_non_termine
    reviewer = create_test_user(email: "future_rev@example.com", first_name: "Fut", last_name: "Rev")
    reviewed = create_test_user(email: "future_rev2@example.com", first_name: "Fut", last_name: "Reviewed")
    sport    = Sport.create!(name: "Football Future", slug: "football_future_test", icon: "⚽")
    # Match dans le futur → pas encore terminé.
    # Celui-ci est dans le futur donc il passe normalement la validation de date.
    match = Match.create!(
      title:       "Match Futur",
      place:       "Terrain",
      date:        Date.tomorrow,
      time:        1.hour.from_now, # dans le futur pour passer la validation 30min
      player_left: 10,
      level:       "Tout niveau", # champ obligatoire
      user:        reviewer,
      sport:       sport
    )
    add_approved_players(match: match, reviewer: reviewer, reviewed: reviewed)

    avis = Avis.new(reviewer: reviewer, reviewed_user: reviewed, match: match, rating: 4)
    refute avis.valid?, "On ne peut pas noter avant la fin du match"
    assert avis.errors[:base].any? { |e| e.include?("fin du match") },
           "L'erreur doit mentionner que le match n'est pas encore terminé"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # CALLBACK — set_mutual_flag
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : quand A note B et que B a déjà noté A → les deux deviennent mutual
  def test_set_mutual_flag_quand_avis_inverse_existe
    user_a = create_test_user(email: "mutual_a@example.com", first_name: "Mutual", last_name: "A")
    user_b = create_test_user(email: "mutual_b@example.com", first_name: "Mutual", last_name: "B")
    match  = create_completed_match(user: user_a)
    add_approved_players(match: match, reviewer: user_a, reviewed: user_b)

    # B note A en premier
    avis_b_vers_a = Avis.create!(reviewer: user_b, reviewed_user: user_a, match: match, rating: 4)
    # À ce stade, l'avis B→A n'est pas encore mutual (A→B n'existe pas)
    refute avis_b_vers_a.reload.mutual, "L'avis B→A ne doit pas être mutual avant que A note B"

    # A note B → le callback set_mutual_flag doit mettre les deux à mutual: true
    avis_a_vers_b = Avis.create!(reviewer: user_a, reviewed_user: user_b, match: match, rating: 5)

    # Les deux avis doivent maintenant être mutuels
    assert avis_a_vers_b.reload.mutual, "L'avis A→B doit être mutual après la création de B→A"
    assert avis_b_vers_a.reload.mutual, "L'avis B→A doit aussi être mutual après la création de A→B"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # CALLBACK — recalculate_average
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : recalculate_average recompute la moyenne sur les avis mutuels uniquement.
  # Attention : set_mutual_flag utilise update_column (sans callbacks), donc la moyenne
  # n'est PAS automatiquement mise à jour après le passage en mutual.
  # Pour recalculer, il faut appeler recalculate_for manuellement ou via un save.
  def test_recalculate_average_met_a_jour_le_profil
    user_a = create_test_user(email: "avg_a@example.com", first_name: "Avg", last_name: "A")
    user_b = create_test_user(email: "avg_b@example.com", first_name: "Avg", last_name: "B")
    match  = create_completed_match(user: user_a)
    add_approved_players(match: match, reviewer: user_a, reviewed: user_b)

    # B→A est créé en premier : pas encore mutual car A→B n'existe pas
    avis_b = Avis.create!(reviewer: user_b, reviewed_user: user_a, match: match, rating: 3)

    # A→B est créé : recalculate_average est appelé (callback after_create)
    # Mais à ce moment, l'avis A→B n'est pas encore mutual → la moyenne reste 0
    avis_a = Avis.create!(reviewer: user_a, reviewed_user: user_b, match: match, rating: 4)

    # set_mutual_flag s'exécute ensuite et marque les deux mutuels via update_column
    # → update_column ne déclenche PAS les callbacks, donc recalculate_average n'est
    # pas rappelé automatiquement. On doit le déclencher manuellement.
    avis_a.send(:recalculate_average)

    # Maintenant que les avis sont mutuels ET la moyenne recalculée, user_b doit avoir 4.0
    assert_equal 4.0, user_b.profil.reload.average_rating,
                 "La moyenne de user_b doit être 4.0 après recalcul sur avis mutual de 4"
  end
end
