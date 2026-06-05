require "test_helper"

# Tests du module SportImagesHelper.
# Ce helper fournit les images Cloudinary pour les sports.
# Méthodes testées :
#   - SPORT_IMAGES      : constante Hash slug → tableau d'URLs
#   - SPORT_MISC_IMAGES : constante Hash avec les images diverses
#   - sport_misc_image  : accès à SPORT_MISC_IMAGES par clé
#   - sport_images_for  : retourne la liste d'URLs pour un slug donné
#   - sport_cover_image : retourne l'URL de couverture d'un match (déterministe)
#
# On utilise ActionView::TestCase qui fournit l'environnement de vue nécessaire.
class SportImagesHelperTest < ActionView::TestCase
  include SportImagesHelper

  parallelize(workers: 1)

  # teardown_db gère l'ordre complet des FK (MatchUser → Match → Sport, etc.)
  teardown { teardown_db }

  # ─── Helpers ─────────────────────────────────────────────────────────────

  # Crée un User avec profil (requis par Match).
  def make_user
    create_test_user(email: "sport_img_#{SecureRandom.hex(4)}@example.com",
                     first_name: "Img", last_name: "Test")
  end

  # Crée un Sport avec le slug donné.
  def make_sport(slug)
    Sport.create!(
      name: slug.capitalize,
      icon: "🏃",
      slug: slug
    )
  end

  # Crée un Match avec les champs requis par les validations.
  # - level: "Tout niveau" passe level_valid_for_sport (backward compat)
  # - player_left: 5 passe validates :player_left, greater_than: 0
  def make_match(user, sport, banner_image: nil)
    Match.create!(
      user:         user,
      sport:        sport,
      date:         Date.tomorrow,
      time:         "14:00:00",
      place:        "Terrain de test",
      level:        "Tout niveau",
      player_left:  5,
      banner_image: banner_image
    )
  end

  # ════════════════════════════════════════════════════════════════════════════
  # SPORT_IMAGES — constante
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : la constante contient les sports principaux.
  test "SPORT_IMAGES contient les sports principaux" do
    %w[football tennis padel volleyball basketball].each do |slug|
      assert SportImagesHelper::SPORT_IMAGES.key?(slug),
             "SPORT_IMAGES doit contenir le slug '#{slug}'"
    end
  end

  # Cas nominal : chaque sport a au moins une image.
  test "SPORT_IMAGES a au moins une image par sport" do
    SportImagesHelper::SPORT_IMAGES.each do |slug, urls|
      assert urls.length >= 1, "#{slug} doit avoir au moins 1 image"
    end
  end

  # Cas nominal : toutes les URLs commencent par https://res.cloudinary.com.
  test "toutes les URLs SPORT_IMAGES sont des URLs Cloudinary" do
    SportImagesHelper::SPORT_IMAGES.each do |slug, urls|
      urls.each do |url|
        assert url.start_with?("https://res.cloudinary.com"),
               "#{slug}: '#{url}' n'est pas une URL Cloudinary valide"
      end
    end
  end

  # ════════════════════════════════════════════════════════════════════════════
  # SPORT_MISC_IMAGES — constante
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : la constante contient les clés attendues.
  test "SPORT_MISC_IMAGES contient les clés multisports et padel_icon" do
    assert SportImagesHelper::SPORT_MISC_IMAGES.key?(:multisports),
           "SPORT_MISC_IMAGES doit avoir la clé :multisports"
    assert SportImagesHelper::SPORT_MISC_IMAGES.key?(:padel_icon),
           "SPORT_MISC_IMAGES doit avoir la clé :padel_icon"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # sport_misc_image
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : sport_misc_image(:multisports) retourne l'URL de l'image.
  test "sport_misc_image retourne l'URL pour une clé valide" do
    url = sport_misc_image(:multisports)
    assert url.present?, "sport_misc_image(:multisports) doit retourner une URL"
    assert url.start_with?("https://"), "L'URL doit commencer par https://"
  end

  # Cas limite : une clé inexistante retourne nil.
  test "sport_misc_image retourne nil pour une clé inexistante" do
    assert_nil sport_misc_image(:inexistant)
  end

  # ════════════════════════════════════════════════════════════════════════════
  # sport_images_for
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : retourne les images football pour le slug "football".
  test "sport_images_for retourne les images du sport demandé" do
    images = sport_images_for("football")
    assert images.length >= 1, "Doit retourner au moins une image pour 'football'"
    assert images.all? { |url| url.include?("/football/") },
           "Les images football doivent contenir '/football/' dans l'URL"
  end

  # Cas limite : un slug inconnu retourne les images football par défaut.
  test "sport_images_for retourne les images football par défaut pour un slug inconnu" do
    images = sport_images_for("sport_inexistant")
    # Le fallback est explicitement les images football
    assert_equal SportImagesHelper::SPORT_IMAGES["football"], images,
                 "Un slug inconnu doit utiliser les images football comme fallback"
  end

  # Cas nominal : fonctionne avec un symbole converti en string.
  test "sport_images_for fonctionne avec un symbol converti en string" do
    images = sport_images_for(:tennis)
    assert images.length >= 1, "Doit fonctionner avec un symbol"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # sport_cover_image
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : si banner_image est définie, elle est retournée directement.
  test "sport_cover_image retourne banner_image si elle est définie" do
    user  = make_user
    sport = make_sport("football_cover")
    match = make_match(user, sport, banner_image: "https://example.com/custom.jpg")

    assert_equal "https://example.com/custom.jpg", sport_cover_image(match),
                 "Quand banner_image est définie, elle doit être retournée directement"
  end

  # Cas nominal : sans banner_image, retourne une URL du tableau du sport.
  test "sport_cover_image retourne une URL Cloudinary si pas de banner_image" do
    user  = make_user
    sport = make_sport("football_auto_cover")
    match = make_match(user, sport)

    url = sport_cover_image(match)
    assert url.present?, "sport_cover_image doit retourner une URL"
    assert url.start_with?("https://res.cloudinary.com"),
           "L'URL doit être une URL Cloudinary"
  end

  # Cas nominal : la sélection d'image est déterministe (même résultat pour le même match).
  test "sport_cover_image est déterministe pour un même match" do
    user  = make_user
    sport = make_sport("football_det")
    match = make_match(user, sport)

    # Appeler deux fois doit retourner le même résultat
    assert_equal sport_cover_image(match), sport_cover_image(match),
                 "sport_cover_image doit être déterministe (même image pour le même match)"
  end
end
