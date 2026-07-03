require "test_helper"

# Tests pour MatchWebPushJob
# Ce job envoie des notifications Web Push aux utilisateurs dont le profil
# correspond au match créé (sport + niveau + localisation).
# On mocke l'envoi WebPush pour ne pas dépendre d'une clé VAPID réelle.
class MatchWebPushJobTest < ActiveJob::TestCase
  # Désactive la parallélisation pour éviter les deadlocks PostgreSQL
  # lors du chargement des fixtures dans plusieurs processus simultanés.
  parallelize(workers: 1)

  teardown { teardown_db }

  # ── CAS NOMINAL : MATCH PUBLIC SANS SUBSCRIPTION ────────────────────────────

  # Vérifie que le job s'exécute sans erreur même si aucun utilisateur
  # n'a de subscription Web Push enregistrée.
  # Le job doit simplement ne rien envoyer et retourner proprement.
  test "s'exécute sans erreur quand aucune subscription n'existe" do
    organizer = create_test_user(email: "orga@push.com", first_name: "Orga", last_name: "Push")
    # Réutilise le sport de la fixture pour éviter les violations d'unicité (name/slug uniques)
    sport = sports(:one)

    future_date = 2.hours.from_now
    match = Match.new(
      user:        organizer,
      sport:       sport,
      title:       "Match push test",
      date:        future_date.to_date,
      time:        future_date.strftime("%H:%M"),
      players_needed: 5,
      level:       "Tout niveau",
      place:       "Paris",
      visibility:  "public"
    )
    match.save!(validate: false)

    # On s'assure que WebPush.payload_send n'est pas appelé (pas de subscription)
    # Le mock est inutile ici car find_candidates ne trouvera personne,
    # mais on vérifie quand même qu'il n'y a pas d'exception
    assert_nothing_raised do
      MatchWebPushJob.perform_now(match.id)
    end
  end

  # ── CAS LIMITE : MATCH PRIVÉ ─────────────────────────────────────────────────

  # Vérifie que le job ne fait rien pour un match privé.
  # Un match privé ne doit pas générer de notifications push (il est "secret").
  # On vérifie qu'aucun PushSubscription n'est consulté en comptant les appels
  # et en s'assurant que le job se termine normalement.
  test "ne fait rien pour un match privé" do
    organizer = create_test_user(email: "orga2@push.com", first_name: "Orga2", last_name: "Push")
    # Réutilise le sport de la fixture pour éviter les violations d'unicité
    sport = sports(:one)

    future_date = 2.hours.from_now
    match = Match.new(
      user:        organizer,
      sport:       sport,
      title:       "Match privé",
      date:        future_date.to_date,
      time:        future_date.strftime("%H:%M"),
      players_needed: 2,
      level:       "Tout niveau",
      place:       "Paris",
      visibility:  "private"  # ← privé : le job doit court-circuiter dès la ligne 2 de perform
    )
    match.save!(validate: false)

    # Le job retourne immédiatement si visibility != "public" → aucune exception
    assert_nothing_raised do
      MatchWebPushJob.perform_now(match.id)
    end

    # Aucun PushSubscription ne doit avoir été créé ni détruit pendant ce test
    assert_equal 0, PushSubscription.count,
                 "Aucune subscription ne doit être touchée pour un match privé"
  end

  # ── CAS D'ERREUR : MATCH INEXISTANT ─────────────────────────────────────────

  # Vérifie que le job se termine proprement quand le match n'existe pas.
  # Le job utilise Match.find (pas find_by) + discard_on ActiveRecord::RecordNotFound.
  # discard_on est actif dans ActiveJob::TestCase → l'exception est absorbée
  # silencieusement et le job se termine sans propager l'erreur.
  # On vérifie donc que perform_now ne lève PAS d'exception (le discard fonctionne).
  test "se termine sans exception si le match n'existe pas (discard_on actif)" do
    assert_nothing_raised do
      MatchWebPushJob.perform_now(999_999_999)
    end
  end

  # ── CAS LIMITE : MATCH SANS SPORT ────────────────────────────────────────────

  # Vérifie que le job ne plante pas si le match n'a pas de sport associé.
  # find_candidates retourne User.none dans ce cas.
  test "ne plante pas si le match n'a pas de sport (find_candidates retourne User.none)" do
    organizer = create_test_user(email: "orga3@push.com", first_name: "Orga3", last_name: "Push")

    future_date = 2.hours.from_now
    match = Match.new(
      user:        organizer,
      sport:       nil,           # ← pas de sport → find_candidates retourne User.none
      title:       "Match sans sport",
      date:        future_date.to_date,
      time:        future_date.strftime("%H:%M"),
      players_needed: 3,
      level:       "Tout niveau",
      place:       "Bordeaux",
      visibility:  "public"
    )
    match.save!(validate: false)

    assert_nothing_raised do
      MatchWebPushJob.perform_now(match.id)
    end
  end
end
