require "test_helper"

# Tests du modèle Match.
# On vérifie les validations (level, player_left, players_present, délai 30 min),
# les scopes (upcoming, publicly_visible, completed, etc.),
# et les méthodes d'instance (private?, full?, urgent?, past?, in_progress?, completed?).
class MatchTest < ActiveSupport::TestCase

  # ─── Helpers ────────────────────────────────────────────────────────────────

  # Crée un User confirmé avec son Profil via create_test_user (test_helper.rb).
  # Sans create_test_user, user.profil serait nil (le Profil n'est pas créé
  # automatiquement par un callback — c'est le RegistrationsController qui le fait).
  def create_user(email: "matchtest_#{SecureRandom.hex(4)}@example.com")
    create_test_user(
      email:      email,
      first_name: "Test",
      last_name:  "User"
    )
  end

  # Retourne les attributs minimaux pour un Match valide dans le futur.
  # date+time = demain 18h → toujours > 30 min dans le futur.
  def valid_match_attrs(overrides = {})
    sport = Sport.find_by(slug: "football") || Sport.create!(name: "Football", slug: "football", icon: "⚽")
    user  = overrides.delete(:user) || create_user
    {
      title:           "Match test",
      date:            Date.tomorrow,
      time:            Time.zone.parse("18:00"),
      players_needed:     4,
      level:           "Débutant",        # niveau valide pour football
      visibility:      "public",
      validation_mode: "automatic",
      genre_restriction: "tous",
      user:            user,
      sport:           sport
    }.merge(overrides)
  end

  # Crée un Match valide en base.
  def create_match(overrides = {})
    Match.create!(valid_match_attrs(overrides))
  end

  # ─── Validations : level ────────────────────────────────────────────────────

  # Cas d'erreur : level vide est rejeté (validates :level, presence: true).
  test "level vide est rejeté" do
    match = Match.new(valid_match_attrs(level: ""))
    assert match.invalid?
    assert match.errors[:level].any?
  end

  # Cas d'erreur : level invalide pour le sport est rejeté.
  test "level invalide pour le sport est rejeté" do
    # "NiveauInexistant" n'est pas dans la grille football
    match = Match.new(valid_match_attrs(level: "NiveauInexistant"))
    assert match.invalid?
    assert match.errors[:level].any?
  end

  # Cas nominal : "Tout niveau" est toujours accepté (backward compat).
  test "Tout niveau est accepté pour tout sport" do
    match = Match.new(valid_match_attrs(level: "Tout niveau"))
    # On désactive la validation du délai 30 min pour ce test en mettant la date au futur
    assert match.valid?, "Attendu valide, erreurs : #{match.errors.full_messages}"
  end

  # ─── Validations : players_needed (capacité cible) ──────────────────────────

  # Cas d'erreur : players_needed absent est rejeté.
  test "players_needed absent est rejeté" do
    match = Match.new(valid_match_attrs(players_needed: nil))
    assert match.invalid?
    assert match.errors[:players_needed].any?
  end

  # Cas d'erreur : players_needed = 0 est rejeté (doit être >= 1).
  test "players_needed égal à 0 est rejeté" do
    match = Match.new(valid_match_attrs(players_needed: 0))
    assert match.invalid?
    assert match.errors[:players_needed].any?
  end

  # Cas d'erreur : players_needed négatif est rejeté.
  test "players_needed négatif est rejeté" do
    match = Match.new(valid_match_attrs(players_needed: -1))
    assert match.invalid?
    assert match.errors[:players_needed].any?
  end

  # Cas nominal : players_needed = 1 est accepté (minimum autorisé).
  test "players_needed de 1 est accepté" do
    match = Match.new(valid_match_attrs(players_needed: 1))
    assert match.valid?, "Attendu valide, erreurs : #{match.errors.full_messages}"
  end

  # ─── Validations : players_present (format Libre) ───────────────────────────

  # Cas d'erreur : players_present absent quand format == "Libre" est rejeté.
  test "players_present absent est rejeté si format est Libre" do
    match = Match.new(valid_match_attrs(format: "Libre", players_present: nil))
    assert match.invalid?
    assert match.errors[:players_present].any?
  end

  # Cas nominal : players_present ignoré si format != "Libre".
  test "players_present absent est accepté si format n'est pas Libre" do
    match = Match.new(valid_match_attrs(format: "5v5", players_present: nil))
    assert match.valid?, "Attendu valide, erreurs : #{match.errors.full_messages}"
  end

  # ─── Validation : délai minimum 30 minutes ──────────────────────────────────

  # Cas d'erreur : match prévu dans moins de 30 min est rejeté.
  test "match dans moins de 30 min est rejeté" do
    match = Match.new(valid_match_attrs(
      date: Date.today,
      time: (Time.current + 10.minutes) # seulement 10 min dans le futur
    ))
    assert match.invalid?
    assert match.errors[:base].any?
  end

  # Cas nominal : match prévu demain est accepté.
  test "match prévu demain est accepté" do
    match = Match.new(valid_match_attrs)
    assert match.valid?, "Attendu valide, erreurs : #{match.errors.full_messages}"
  end

  # ─── Scopes ─────────────────────────────────────────────────────────────────

  # upcoming : exclut les matchs déjà passés.
  test "scope upcoming exclut les matchs passés" do
    futur = create_match(date: Date.tomorrow, time: Time.zone.parse("18:00"))
    # On force un match "passé" directement en base (bypass validations)
    passe = create_match(date: Date.tomorrow, time: Time.zone.parse("18:00"))
    passe.update_columns(date: 2.days.ago, time: Time.zone.parse("10:00"))

    results = Match.upcoming
    assert_includes     results, futur
    assert_not_includes results, passe
  end

  # publicly_visible : exclut les matchs privés.
  test "scope publicly_visible exclut les matchs privés" do
    public_m  = create_match(visibility: "public")
    # Un match privé → le token est généré automatiquement par before_create
    private_m = create_match(visibility: "private")

    results = Match.publicly_visible
    assert_includes     results, public_m
    assert_not_includes results, private_m
  end

  # completed : retourne les matchs terminés (> 1h après le début).
  # On crée le match en bypassant la validation 30min via update_columns.
  # La date DOIT être dans le passé (> 1h) pour que le scope completed le retourne.
  test "scope completed retourne les matchs terminés" do
    # Match terminé : on crée d'abord un match valide (futur), puis on le force dans le passé
    termine = create_match
    # update_columns bypasse les validations → on peut mettre une date passée
    termine.update_columns(
      date: Date.yesterday,          # hier
      time: 2.hours.ago.strftime("%H:%M:%S")  # il y a 2 heures
    )

    # Match futur : ne doit pas apparaître dans completed
    futur = create_match

    results = Match.completed
    assert_includes     results, termine
    assert_not_includes results, futur
  end

  # active_for_user : inclut les matchs pas encore terminés (>= il y a 1h).
  test "scope active_for_user inclut les matchs futurs" do
    futur = create_match
    results = Match.active_for_user
    assert_includes results, futur
  end

  test "scope active_for_user exclut les matchs terminés depuis plus d'1h" do
    vieux = create_match
    vieux.update_columns(
      date: 3.hours.ago.to_date,
      time: (3.hours.ago).strftime("%H:%M:%S")
    )
    results = Match.active_for_user
    assert_not_includes results, vieux
  end

  # visible_for_genre : avec un user femme, tous les matchs sont visibles.
  test "visible_for_genre avec user femme retourne tous les matchs" do
    user_femme = create_user(email: "femme_scope@example.com")
    user_femme.update_column(:genre, "femme")

    match_tous    = create_match(genre_restriction: "tous")
    match_feminin = create_match(genre_restriction: "feminin")

    results = Match.visible_for_genre(user_femme)
    assert_includes results, match_tous
    assert_includes results, match_feminin
  end

  # visible_for_genre : avec un user non-femme, les matchs féminins sont exclus.
  test "visible_for_genre avec user non-femme exclut les matchs féminins" do
    user_homme = create_user(email: "homme_scope@example.com")
    user_homme.update_column(:genre, "homme")

    match_tous    = create_match(genre_restriction: "tous")
    match_feminin = create_match(genre_restriction: "feminin")

    results = Match.visible_for_genre(user_homme)
    assert_includes     results, match_tous
    assert_not_includes results, match_feminin
  end

  # visible_for_genre : avec un visiteur nil, les matchs féminins sont exclus.
  test "visible_for_genre avec user nil exclut les matchs féminins" do
    match_tous    = create_match(genre_restriction: "tous")
    match_feminin = create_match(genre_restriction: "feminin")

    results = Match.visible_for_genre(nil)
    assert_includes     results, match_tous
    assert_not_includes results, match_feminin
  end

  # ─── Méthodes d'instance ────────────────────────────────────────────────────

  # private? retourne vrai si visibility == "private".
  test "private? retourne vrai pour un match privé" do
    match = create_match(visibility: "private")
    assert match.private?
  end

  test "private? retourne faux pour un match public" do
    match = create_match(visibility: "public")
    assert_not match.private?
  end

  # public? retourne vrai si visibility == "public".
  test "public? retourne vrai pour un match public" do
    match = create_match(visibility: "public")
    assert match.public?
  end

  # full? retourne vrai si player_left <= 0.
  test "full? retourne vrai si player_left est 0" do
    match = create_match
    match.update_column(:player_left, 0)
    assert match.full?
  end

  test "full? retourne faux si player_left est positif" do
    match = create_match
    match.update_column(:player_left, 2)
    assert_not match.full?
  end

  # urgent? retourne vrai si le match a lieu dans moins de 2h et est dans le futur.
  # Note : on utilise travel_to à midi pour éviter le problème DST de PostgreSQL.
  # Les colonnes :time sont stockées comme chaîne locale et relues avec le décalage
  # de la date de référence 2000-01-01 (hiver CET, +01:00), ce qui crée un décalage
  # de 1h en été (CEST, +02:00). En partant de midi, +1h ne passe jamais minuit.
  test "urgent? retourne vrai si match dans moins de 2h" do
    match = create_match
    # On gèle le temps à 12h00 un jour d'été (juillet) pour travailler loin de minuit
    travel_to Time.zone.local(2030, 7, 15, 12, 0, 0) do
      # Match à 13h00 → 1h dans le futur → urgent
      match.update_columns(date: Date.new(2030, 7, 15), time: "13:00:00")
      assert match.urgent?
    end
  end

  test "urgent? retourne faux si match dans plus de 2h" do
    match = create_match
    # Match 5 jours plus tard à midi → bien plus de 2h dans le futur
    # Utilise "12:00:00" pour rester loin de minuit et éviter tout problème DST
    match.update_columns(date: 5.days.from_now.to_date, time: "12:00:00")
    assert_not match.urgent?
  end

  # past? retourne vrai si la date+heure est dépassée.
  test "past? retourne vrai pour un match passé" do
    match = create_match
    match.update_columns(
      date: 2.days.ago.to_date,
      time: Time.zone.parse("10:00").strftime("%H:%M:%S")
    )
    assert match.past?
  end

  test "past? retourne faux pour un match futur" do
    match = create_match
    assert_not match.past?
  end

  # in_progress? retourne vrai si le match a débuté il y a moins d'1h.
  # IMPORTANT sur la colonne :time : Rails stocke les colonnes :time en UTC+1 (offset fixe).
  # Si on passe strftime ou Time.zone.local directement dans update_columns, la valeur
  # est mal interprétée lors du rechargement (décalage de 1h).
  # Solution fiable : assigner via l'attribut setter (match.time = ...) pour que Rails
  # effectue la conversion interne, PUIS lire match.time (déjà converti) pour update_columns.
  test "in_progress? retourne vrai si match débuté il y a 30 min" do
    match = create_match
    thirty_ago = Time.zone.now - 30.minutes
    # On assigne via le setter pour déclencher la conversion Rails du fuseau horaire
    match.time = thirty_ago
    # On lit la valeur déjà convertie par Rails et on la passe à update_columns
    converted_time = match.time
    match.update_columns(
      date: thirty_ago.to_date,
      time: converted_time
    )
    match.reload
    assert match.in_progress?, "build_datetime=#{match.build_datetime}, now=#{Time.current}"
  end

  test "in_progress? retourne faux si match débuté il y a plus d'1h" do
    match = create_match
    match.update_columns(
      date: 2.hours.ago.to_date,
      time: (2.hours.ago).strftime("%H:%M:%S")
    )
    assert_not match.in_progress?
  end

  # completed? retourne vrai si le match a débuté il y a plus d'1h.
  test "completed? retourne vrai si match débuté il y a 2h" do
    match = create_match
    match.update_columns(
      date: 2.hours.ago.to_date,
      time: (2.hours.ago).strftime("%H:%M:%S")
    )
    assert match.completed?
  end

  test "completed? retourne faux pour un match futur" do
    match = create_match
    assert_not match.completed?
  end

  # ─── Callback : generate_private_token ──────────────────────────────────────

  # Cas nominal : un match privé reçoit un token avant création.
  test "generate_private_token est appelé avant création d'un match privé" do
    match = create_match(visibility: "private")
    assert match.private_token.present?, "Le private_token devrait être généré"
  end

  # Cas nominal : un match public n'a pas de token.
  test "un match public n'a pas de private_token" do
    match = create_match(visibility: "public")
    assert_nil match.private_token
  end

  # Edge case : deux matchs privés ont des tokens différents (unicité).
  test "deux matchs privés ont des tokens différents" do
    match1 = create_match(visibility: "private")
    match2 = create_match(visibility: "private")
    assert_not_equal match1.private_token, match2.private_token
  end
end
