require "test_helper"

# Tests du module ApplicationHelper.
# Ce helper fournit des méthodes de rendu réutilisables dans toutes les vues :
#   - achievement_badge  : génère le HTML d'un badge achievement
#   - user_avatar_tag    : génère un avatar (image ou initiales)
#   - sport_icon         : affiche l'icône d'un sport (emoji ou image)
#   - level_badge_css    : retourne la classe CSS d'un badge de niveau
#   - sport_icon_text    : retourne l'icône en texte brut (pour data-* et selects)
#   - sport_icon_html_attr : retourne le HTML encodé pour les attributs data-label-html
#
# On utilise ActionView::TestCase qui fournit l'environnement de vue Rails
# nécessaire pour appeler les helpers (content_tag, image_tag, etc.).
class ApplicationHelperTest < ActionView::TestCase
  # Inclure le helper testé dans le contexte de test
  include ApplicationHelper

  parallelize(workers: 1)

  teardown do
    # UserAchievement doit être supprimé avant Achievement (FK)
    UserAchievement.delete_all
    Achievement.delete_all
    # teardown_db gère l'ordre complet des FK (Match avant Sport, Profil avant User, etc.)
    teardown_db
  end

  # ─── Helpers ────────────────────────────────────────────────────────────────

  # Crée un Achievement valide avec une clé unique.
  def make_achievement(overrides = {})
    Achievement.create!({
      key:         "helper_test_#{SecureRandom.hex(4)}",
      name:        "Badge Test",
      description: "Description test",
      xp_reward:   20,
      icon_emoji:  "🏆"
    }.merge(overrides))
  end

  # Crée un Sport avec une icône emoji (pas d'image).
  def make_sport_emoji(name = "FootballHelp#{SecureRandom.hex(3)}")
    Sport.create!(name: name, icon: "⚽", slug: name.downcase.gsub(" ", "_"))
  end

  # Crée un Sport avec une icône image (URL PNG).
  def make_sport_image(name = "TennisHelp#{SecureRandom.hex(3)}")
    Sport.create!(
      name: name,
      icon: "https://res.cloudinary.com/example/image/upload/sport.png",
      slug: name.downcase.gsub(" ", "_")
    )
  end

  # ════════════════════════════════════════════════════════════════════════════
  # achievement_badge
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un badge débloqué contient la classe CSS de glow vert.
  test "achievement_badge débloqué contient la bordure verte" do
    achievement = make_achievement
    html        = achievement_badge(achievement, is_unlocked: true)
    # Le badge débloqué a une bordure verte (#1EDD88)
    assert_includes html, "#1EDD88",
                    "Le badge débloqué doit avoir une bordure verte"
  end

  # Cas nominal : un badge verrouillé applique grayscale à l'emoji.
  test "achievement_badge verrouillé applique grayscale" do
    achievement = make_achievement
    html        = achievement_badge(achievement, is_unlocked: false)
    # Le badge verrouillé applique filter:grayscale(1) sur l'emoji
    assert_includes html, "grayscale",
                    "Le badge verrouillé doit appliquer un filtre grayscale"
  end

  # Cas nominal : le HTML du badge contient l'emoji de l'achievement.
  test "achievement_badge contient l'emoji de l'achievement" do
    achievement = make_achievement(icon_emoji: "🎯")
    html        = achievement_badge(achievement, is_unlocked: true)
    assert_includes html, "🎯", "Le badge doit contenir l'emoji de l'achievement"
  end

  # Cas limite : si icon_emoji est nil ou vide, le badge utilise l'emoji par défaut 🏅.
  test "achievement_badge utilise l'emoji 🏅 par défaut si icon_emoji est vide" do
    achievement = make_achievement(icon_emoji: nil)
    html        = achievement_badge(achievement, is_unlocked: false)
    assert_includes html, "🏅",
                    "Sans icon_emoji, le badge doit afficher 🏅"
  end

  # Cas nominal : le badge contient les données Stimulus nécessaires.
  test "achievement_badge contient les attributs data Stimulus" do
    achievement = make_achievement
    html        = achievement_badge(achievement, is_unlocked: true)
    # Le controller Stimulus est achievement-modal
    assert_includes html, "achievement-modal",
                    "Le badge doit référencer le controller Stimulus achievement-modal"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # user_avatar_tag
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un user sans avatar affiche ses initiales.
  test "user_avatar_tag affiche les initiales quand pas d'avatar" do
    user = create_test_user(email: "avatar_helper@example.com",
                            first_name: "Alice", last_name: "Test")
    html = user_avatar_tag(user)
    # Les initiales doivent être "AT" (Alice Test)
    assert_includes html, "AT",
                    "Sans avatar, le tag doit afficher les initiales de l'utilisateur"
  end

  # Cas nominal : l'avatar a un rôle ARIA pour l'accessibilité.
  test "user_avatar_tag sans avatar a le rôle ARIA img" do
    user = create_test_user(email: "aria_avatar@example.com",
                            first_name: "Bob", last_name: "ARIA")
    html = user_avatar_tag(user)
    assert_includes html, 'role="img"',
                    "L'avatar initiales doit avoir role='img' pour l'accessibilité"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # sport_icon
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un sport avec une icône emoji retourne un span contenant l'emoji.
  test "sport_icon retourne un span pour une icône emoji" do
    sport = make_sport_emoji
    html  = sport_icon(sport)
    assert_includes html, "⚽",
                    "sport_icon doit retourner l'emoji dans un span"
  end

  # Cas nominal : un sport avec une icône image retourne une balise img.
  test "sport_icon retourne une img pour une icône image" do
    sport = make_sport_image
    html  = sport_icon(sport)
    assert_includes html, "<img",
                    "sport_icon doit retourner une balise img pour une URL image"
  end

  # Cas limite : sport nil → retourne une chaîne vide.
  test "sport_icon retourne une chaîne vide si sport est nil" do
    assert_equal "", sport_icon(nil),
                 "sport_icon(nil) doit retourner une chaîne vide"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # level_badge_css
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : "Tout niveau" ou valeur vide retourne "level-tout".
  test "level_badge_css retourne level-tout pour 'Tout niveau'" do
    assert_equal "level-tout", level_badge_css("Tout niveau")
  end

  test "level_badge_css retourne level-tout pour une valeur vide" do
    assert_equal "level-tout", level_badge_css("")
  end

  test "level_badge_css retourne level-tout pour nil" do
    assert_equal "level-tout", level_badge_css(nil)
  end

  # Cas nominal : "Débutant" retourne "level-tier-1" (sans contexte sport).
  test "level_badge_css retourne level-tier-1 pour Débutant" do
    assert_equal "level-tier-1", level_badge_css("Débutant")
  end

  # Cas nominal : "Expert" retourne "level-tier-7" (sans contexte sport).
  test "level_badge_css retourne level-tier-7 pour Expert" do
    assert_equal "level-tier-7", level_badge_css("Expert")
  end

  # Cas nominal : un label inconnu sans contexte sport retourne "level-tout".
  test "level_badge_css retourne level-tout pour un label inconnu" do
    assert_equal "level-tout", level_badge_css("NiveauInconnu123")
  end

  # ════════════════════════════════════════════════════════════════════════════
  # sport_icon_text
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : retourne l'emoji pour un sport avec icône emoji.
  test "sport_icon_text retourne l'emoji pour une icône non-image" do
    sport = make_sport_emoji
    assert_equal "⚽", sport_icon_text(sport)
  end

  # Cas nominal : retourne une chaîne vide pour un sport avec icône image.
  test "sport_icon_text retourne une chaîne vide pour une icône image" do
    sport = make_sport_image
    assert_equal "", sport_icon_text(sport)
  end

  # Cas limite : sport nil → retourne une chaîne vide.
  test "sport_icon_text retourne une chaîne vide si sport est nil" do
    assert_equal "", sport_icon_text(nil)
  end

  # ════════════════════════════════════════════════════════════════════════════
  # sport_icon_html_attr
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : retourne "⚽ NomDuSport" pour une icône emoji.
  test "sport_icon_html_attr retourne emoji + nom pour une icône emoji" do
    sport  = make_sport_emoji("FootballAttr")
    result = sport_icon_html_attr(sport)
    assert_includes result, "⚽"
    assert_includes result, "FootballAttr"
  end

  # Cas nominal : retourne une chaîne contenant <img pour une icône image.
  test "sport_icon_html_attr retourne du HTML avec img pour une icône image" do
    sport  = make_sport_image("TennisAttr")
    result = sport_icon_html_attr(sport)
    assert_includes result, "<img",
                    "sport_icon_html_attr doit retourner du HTML avec img pour une icône image"
  end

  # Cas limite : sport nil → retourne une chaîne vide.
  test "sport_icon_html_attr retourne une chaîne vide si sport est nil" do
    assert_equal "", sport_icon_html_attr(nil)
  end

  # ── Fil d'Ariane ────────────────────────────────────────────────────────────
  # L'accueil est ajouté par le helper : les vues ne le passent jamais, sinon
  # chacune finirait par l'écrire à sa façon.
  test "breadcrumb_for préfixe le fil par l'accueil" do
    html = breadcrumb_for([["Tournois", "/tournois"], ["Open de printemps", nil]])

    assert_includes html, "Accueil"
    assert_includes html, "Open de printemps"
    assert_includes html, %(aria-label="Fil d'Ariane")
  end

  # Le dernier maillon est la page courante : jamais un lien.
  test "breadcrumb_for ne lie pas la page courante" do
    html = breadcrumb_for([["Tournois", "/tournois"], ["Open de printemps", nil]])

    assert_includes html, '<a class="breadcrumb-trail__link" href="/tournois">Tournois</a>'
    assert_includes html, 'aria-current="page"'
    assert_no_match(/<a[^>]*>\s*Open de printemps/, html)
  end

  # Un libellé long ferait déborder le fil sur mobile. Seul l'AFFICHAGE est
  # tronqué : le JSON-LD garde le nom complet, c'est celui-là que Google indexe.
  test "breadcrumb_for tronque l'affichage mais pas le JSON-LD" do
    html = breadcrumb_for([["A" * 80, nil]])
    nav  = html[/<nav.*?<\/nav>/m]

    assert_includes nav, "..."
    assert_not_includes nav, "A" * 80
    assert_includes html[/<script.*?<\/script>/m], "A" * 80
  end

  # schema.org exige des URLs absolues : un chemin relatif y est ignoré.
  test "breadcrumb_json_ld rend des URLs absolues et omet la page courante" do
    json = JSON.parse(breadcrumb_json_ld([["Accueil", "/"], ["Tournois", "/tournois"], ["Open", nil]]))
    items = json["itemListElement"]

    assert_equal "BreadcrumbList", json["@type"]
    assert_equal [1, 2, 3], items.map { |i| i["position"] }
    assert_match %r{\Ahttps?://.+/tournois\z}, items[1]["item"]
    assert_nil items[2]["item"], "la page courante ne doit pas porter d'item"
  end
end
