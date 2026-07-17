require "test_helper"

# Tests du modèle Sport.
# Un Sport représente une discipline sportive (Football, Tennis, Padel, etc.)
# avec un nom, un slug URL-friendly et une icône emoji.
# IMPORTANT : icon: "" est INVALIDE (validates :icon, presence: true). Toujours passer un emoji.
# Méthodes importantes :
#   - available_formats    → retourne les formats de jeu selon le sport (ne nécessite pas de persistance)
#   - available_levels     → retourne les niveaux selon le sport (ne nécessite pas de persistance)
#   - default_player_count → nombre de joueurs du premier format
#   - max_player_count     → nombre de joueurs du format le plus grand
class SportTest < ActiveSupport::TestCase
  teardown { teardown_db }

  # ════════════════════════════════════════════════════════════════════════════
  # RÈGLES DE SCORE (Lot 4 Tournoi)
  # ════════════════════════════════════════════════════════════════════════════

  def test_scoring_rules_tennis_padel_best_of_3
    %w[tennis padel].each do |slug|
      rules = Sport.new(slug: slug).scoring_rules
      assert_equal 3, rules[:best_of]
      assert_equal 6, rules[:target]
      assert rules[:win_by_two]
    end
  end

  def test_scoring_rules_ping_pong_best_of_5_win_by_two
    rules = Sport.new(slug: "ping-pong").scoring_rules
    assert_equal 5, rules[:best_of]
    assert_equal 11, rules[:target]
    assert rules[:win_by_two]
    assert_nil rules[:cap]
  end

  def test_scoring_rules_badminton_cap_30
    rules = Sport.new(slug: "badminton").scoring_rules
    assert_equal 21, rules[:target]
    assert_equal 30, rules[:cap]
  end

  def test_scoring_rules_fallback_sans_win_by_two
    rules = Sport.new(slug: "inconnu").scoring_rules
    assert_equal 3, rules[:best_of]
    refute rules[:win_by_two]
  end

  # ════════════════════════════════════════════════════════════════════════════
  # VALIDATIONS
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un sport avec name, slug et icon (non vide) est valide
  def test_sport_valide_avec_tous_les_champs
    # icon: "" est invalide → on passe un emoji réel
    sport = Sport.new(name: "Handball Test", slug: "handball_test", icon: "🤾")
    assert sport.valid?, "Un sport avec name, slug et icon non-vide doit être valide : #{sport.errors.full_messages}"
  end

  # Cas d'erreur : le name est obligatoire
  def test_sport_invalide_sans_name
    # icon doit être non-vide pour que la seule erreur visible soit sur :name
    sport = Sport.new(name: nil, slug: "without-name", icon: "🤾")
    refute sport.valid?, "Un sport sans name doit être invalide"
    assert_includes sport.errors[:name], "ne peut pas être vide"
  end

  # Cas d'erreur : le slug est obligatoire
  def test_sport_invalide_sans_slug
    sport = Sport.new(name: "Sport Sans Slug", slug: nil, icon: "🤾")
    refute sport.valid?, "Un sport sans slug doit être invalide"
    assert_includes sport.errors[:slug], "ne peut pas être vide"
  end

  # Cas d'erreur : l'icon est obligatoire (ne peut pas être nil ni "")
  def test_sport_invalide_sans_icon
    sport = Sport.new(name: "Sport Sans Icon", slug: "sport-sans-icon", icon: nil)
    refute sport.valid?, "Un sport sans icon doit être invalide"
    assert_includes sport.errors[:icon], "ne peut pas être vide"
  end

  # Edge case : icon vide ("") est aussi invalide (présence requise)
  def test_sport_invalide_avec_icon_vide
    sport = Sport.new(name: "Sport Icon Vide", slug: "sport-icon-vide", icon: "")
    refute sport.valid?, "Un sport avec icon vide ('') doit être invalide"
    assert sport.errors[:icon].any?, "Une erreur sur :icon doit être présente"
  end

  # Cas d'erreur : deux sports ne peuvent pas avoir le même name
  def test_sport_invalide_si_name_duplique
    # On utilise save (sans !) pour éviter l'erreur de traduction i18n manquante en fr
    first = Sport.new(name: "Unique Sport", slug: "unique-sport", icon: "🏈")
    first.save # on ignore l'éventuel échec de création (sport déjà présent)
    doublon = Sport.new(name: "Unique Sport", slug: "autre-slug-uniq", icon: "🏈")
    refute doublon.valid?, "Deux sports ne peuvent pas avoir le même name"
    # Le message d'unicité peut être traduit ou non selon la config i18n
    assert doublon.errors[:name].any?, "Une erreur d'unicité doit être présente sur :name"
  end

  # Cas d'erreur : deux sports ne peuvent pas avoir le même slug
  def test_sport_invalide_si_slug_duplique
    first = Sport.new(name: "Sport A", slug: "sport-slug-dup", icon: "⚽")
    first.save
    doublon = Sport.new(name: "Sport B", slug: "sport-slug-dup", icon: "⚽")
    refute doublon.valid?, "Deux sports ne peuvent pas avoir le même slug"
    assert doublon.errors[:slug].any?, "Une erreur d'unicité doit être présente sur :slug"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # METHODES : available_formats
  # Ces méthodes utilisent uniquement le slug → pas besoin de persister le sport
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : available_formats retourne les bons formats pour le football
  def test_available_formats_pour_football
    # On n'a pas besoin de persister le sport pour appeler available_formats
    sport = Sport.new(name: "Football", slug: "football", icon: "⚽")
    formats = sport.available_formats
    labels  = formats.map { |f| f[:label] }
    assert_includes labels, "5v5",   "Football doit inclure le format 5v5"
    assert_includes labels, "11v11", "Football doit inclure le format 11v11"
    assert_includes labels, "Libre", "Football doit inclure le format Libre"
  end

  # Cas nominal : available_formats pour le padel retourne uniquement 2v2 + Libre
  def test_available_formats_pour_padel
    sport  = Sport.new(name: "Padel", slug: "padel", icon: "🎾")
    formats = sport.available_formats
    labels  = formats.map { |f| f[:label] }
    assert_includes labels, "2v2",   "Padel doit inclure le format 2v2"
    assert_includes labels, "Libre", "Padel doit inclure le format Libre"
  end

  # Edge case : un sport avec un slug inconnu retourne uniquement le format Libre
  def test_available_formats_sport_inconnu_retourne_libre
    sport   = Sport.new(name: "Curling", slug: "curling", icon: "🥌")
    formats = sport.available_formats
    assert_equal 1, formats.size, "Un sport inconnu doit retourner exactement 1 format (Libre)"
    assert_equal "Libre", formats.first[:label], "Ce format unique doit être 'Libre'"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # METHODES : available_levels
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : available_levels pour le tennis retourne la grille officielle FFT (6 niveaux)
  def test_available_levels_pour_tennis
    sport  = Sport.new(name: "Tennis", slug: "tennis", icon: "🎾")
    levels = sport.available_levels
    labels = levels.map { |l| l[:label] }
    assert_includes labels, "Débutant", "Tennis doit inclure le niveau Débutant"
    assert_includes labels, "Expert",   "Tennis doit inclure le niveau Expert"
    assert_equal 6, labels.size, "Tennis doit avoir 6 niveaux selon la grille FFT"
  end

  # Cas nominal : available_levels pour le football retourne 5 niveaux génériques
  def test_available_levels_pour_football
    sport  = Sport.new(name: "Football", slug: "football", icon: "⚽")
    levels = sport.available_levels
    assert_equal 5, levels.size, "Football doit avoir 5 niveaux"
  end

  # Edge case : un sport avec slug inconnu retourne le fallback générique (3 niveaux)
  def test_available_levels_sport_inconnu_retourne_fallback
    sport  = Sport.new(name: "Ping-pong", slug: "ping-pong", icon: "🏓")
    levels = sport.available_levels
    assert_equal 3, levels.size, "Un sport inconnu doit retourner le fallback générique (3 niveaux)"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # METHODES : default_player_count et max_player_count
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : default_player_count pour le football = 9 (format 5v5 : 9 joueurs manquants)
  def test_default_player_count_pour_football
    sport = Sport.new(name: "Football", slug: "football", icon: "⚽")
    assert_equal 9, sport.default_player_count,
                 "default_player_count pour football doit être 9 (format 5v5)"
  end

  # Cas nominal : max_player_count pour le football = 21 (format 11v11)
  def test_max_player_count_pour_football
    sport = Sport.new(name: "Football", slug: "football", icon: "⚽")
    assert_equal 21, sport.max_player_count,
                 "max_player_count pour football doit être 21 (format 11v11)"
  end

  # Edge case : max_player_count ignore les formats "Libre" (players: nil)
  def test_max_player_count_ignore_le_format_libre
    sport = Sport.new(name: "Padel", slug: "padel", icon: "🎾")
    # Padel : [{ label: "2v2", players: 3 }, { label: "Libre", players: nil }]
    # compact + max ignorent nil → doit retourner 3
    assert_equal 3, sport.max_player_count,
                 "max_player_count ne doit pas retourner nil (le format Libre est ignoré par compact)"
  end
end
