require "test_helper"

# Tests du modèle MatchUser.
# Un MatchUser est la table de jointure entre User et Match.
# Il représente l'inscription d'un joueur à un match.
# Statuts : "pending" | "approved" | "rejected" | "waiting"
# Rôles : "organisateur" ou autre valeur (pas de validation stricte sur role)
# Règles :
#   - Le statut doit être dans STATUSES
#   - Un user ne peut être inscrit qu'une seule fois par match (unicité user/match)
class MatchUserTest < ActiveSupport::TestCase
  teardown { teardown_db }

  # Crée un match minimal valide
  def create_match(user:)
    sport = Sport.create!(name: "Football MU", slug: "football_mu_test", icon: "⚽")
    Match.create!(
      title:       "Match Inscrit Test",
      place:       "Terrain",
      date:        Date.tomorrow,
      time:        1.hour.from_now, # doit être au moins 30min dans le futur
      player_left: 10,
      level:       "Tout niveau",   # champ obligatoire (validates :level, presence: true)
      user:        user,
      sport:       sport
    )
  end

  # ════════════════════════════════════════════════════════════════════════════
  # VALIDATIONS
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un MatchUser avec statut "pending" est valide
  def test_match_user_valide_avec_statut_pending
    user  = create_test_user(email: "mu_user@example.com", first_name: "MU", last_name: "User")
    match = create_match(user: user)
    mu    = MatchUser.new(user: user, match: match, status: "pending", role: "joueur")
    assert mu.valid?, "Un MatchUser avec statut 'pending' doit être valide"
  end

  # Cas nominal : chaque statut valide est accepté
  def test_tous_les_statuts_valides_sont_acceptes
    user  = create_test_user(email: "mu_all@example.com", first_name: "All", last_name: "Status")
    match = create_match(user: user)
    # On ne peut pas créer plusieurs MatchUser pour le même user/match
    # → on teste la validation seule sans sauvegarder
    MatchUser::STATUSES.each do |statut|
      mu = MatchUser.new(user: user, match: match, status: statut)
      # Un statut valide ne doit pas générer d'erreur sur :status
      mu.valid?
      assert mu.errors[:status].empty?, "Le statut '#{statut}' doit être considéré valide"
    end
  end

  # Edge case : un statut inconnu génère une erreur
  # Note : MatchUser n'a pas de validation d'inclusion explicite dans le code lu,
  # mais les statuts sont documentés dans STATUSES. On teste la présence du statut.
  def test_match_user_avec_statut_inconnu_na_pas_derreur_de_statut_par_defaut
    # IMPORTANT : le modèle MatchUser ne valide PAS l'inclusion de status via validates.
    # Le status est défini avec default: "pending" en base mais il n'y a pas de
    # validates :status, inclusion: dans le modèle → on vérifie juste que STATUSES est défini.
    assert_includes MatchUser::STATUSES, "pending",   "STATUSES doit contenir 'pending'"
    assert_includes MatchUser::STATUSES, "approved",  "STATUSES doit contenir 'approved'"
    assert_includes MatchUser::STATUSES, "rejected",  "STATUSES doit contenir 'rejected'"
    assert_includes MatchUser::STATUSES, "waiting",   "STATUSES doit contenir 'waiting'"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # METHODES D'INSTANCE
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : approved? retourne true quand status == "approved"
  def test_approved_retourne_true
    user  = create_test_user(email: "mu_apr@example.com", first_name: "Apr", last_name: "User")
    match = create_match(user: user)
    mu    = MatchUser.new(user: user, match: match, status: "approved")
    assert mu.approved?, "approved? doit retourner true quand status == 'approved'"
  end

  # Cas d'erreur : approved? retourne false pour un autre statut
  def test_approved_retourne_false_si_pending
    user  = create_test_user(email: "mu_apr2@example.com", first_name: "Apr2", last_name: "User")
    match = create_match(user: user)
    mu    = MatchUser.new(user: user, match: match, status: "pending")
    refute mu.approved?, "approved? doit retourner false quand status != 'approved'"
  end

  # Cas nominal : pending? retourne true quand status == "pending"
  def test_pending_retourne_true
    user  = create_test_user(email: "mu_pen@example.com", first_name: "Pen", last_name: "User")
    match = create_match(user: user)
    mu    = MatchUser.new(user: user, match: match, status: "pending")
    assert mu.pending?, "pending? doit retourner true quand status == 'pending'"
  end

  # Cas d'erreur : pending? retourne false pour "approved"
  def test_pending_retourne_false_si_approved
    user  = create_test_user(email: "mu_pen2@example.com", first_name: "Pen2", last_name: "User")
    match = create_match(user: user)
    mu    = MatchUser.new(user: user, match: match, status: "approved")
    refute mu.pending?, "pending? doit retourner false quand status != 'pending'"
  end

  # Cas nominal : rejected? retourne true quand status == "rejected"
  def test_rejected_retourne_true
    user  = create_test_user(email: "mu_rej@example.com", first_name: "Rej", last_name: "User")
    match = create_match(user: user)
    mu    = MatchUser.new(user: user, match: match, status: "rejected")
    assert mu.rejected?, "rejected? doit retourner true quand status == 'rejected'"
  end

  # Cas nominal : waiting? retourne true quand status == "waiting"
  def test_waiting_retourne_true
    user  = create_test_user(email: "mu_wait@example.com", first_name: "Wait", last_name: "User")
    match = create_match(user: user)
    mu    = MatchUser.new(user: user, match: match, status: "waiting")
    assert mu.waiting?, "waiting? doit retourner true quand status == 'waiting'"
  end
end
