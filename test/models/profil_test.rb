require "test_helper"

# Tests du modèle Profil.
# On vérifie les validations (first_name, last_name, preferred_city),
# le système XP/niveaux et toutes les méthodes d'instance.
class ProfilTest < ActiveSupport::TestCase

  # ─── Helpers ────────────────────────────────────────────────────────────────

  # Crée un User confirmé + son Profil associé via create_test_user (test_helper.rb).
  # create_test_user gère les deux étapes :
  #   1. User.create! avec first_name/last_name (attr_accessor validés on: :create)
  #   2. user.create_profil! pour que user.profil ne soit pas nil
  # Les overrides supplémentaires sont appliqués sur le profil après création.
  def create_user_with_profil(overrides = {})
    # On extrait first_name/last_name s'ils sont dans les overrides
    first_name = overrides.delete(:first_name) || "Alice"
    last_name  = overrides.delete(:last_name)  || "Dupont"
    email      = "profil_#{SecureRandom.hex(4)}@example.com"

    # create_test_user crée le User ET son Profil en une seule opération
    user = create_test_user(
      email:      email,
      first_name: first_name,
      last_name:  last_name
    )

    # Si des attributs supplémentaires sont fournis, on les applique sur le profil
    # update_columns contourne les validations pour pouvoir tester des états précis
    user.profil.update!(overrides) if overrides.any?
    user.profil
  end

  # ─── Validations ────────────────────────────────────────────────────────────

  # Cas nominal : un profil avec first_name et last_name est valide.
  test "profil avec first_name et last_name est valide" do
    profil = create_user_with_profil
    assert profil.valid?, "Attendu valide, erreurs : #{profil.errors.full_messages}"
  end

  # Cas d'erreur : first_name vide est rejeté.
  test "first_name vide est rejeté" do
    profil = create_user_with_profil
    profil.first_name = ""
    assert profil.invalid?
    assert profil.errors[:first_name].any?
  end

  # Cas d'erreur : last_name vide est rejeté.
  test "last_name vide est rejeté" do
    profil = create_user_with_profil
    profil.last_name = ""
    assert profil.invalid?
    assert profil.errors[:last_name].any?
  end

  # Cas nominal : preferred_city vide est autorisé (champ optionnel).
  test "preferred_city vide est autorisé" do
    profil = create_user_with_profil
    profil.preferred_city = ""
    assert profil.valid?
  end

  # Cas d'erreur : preferred_city dépassant 100 caractères est rejeté.
  test "preferred_city de plus de 100 caractères est rejeté" do
    profil = create_user_with_profil
    profil.preferred_city = "a" * 101
    assert profil.invalid?
    assert profil.errors[:preferred_city].any?
  end

  # Edge case : preferred_city de exactement 100 caractères est accepté.
  test "preferred_city de 100 caractères est accepté" do
    profil = create_user_with_profil
    profil.preferred_city = "a" * 100
    assert profil.valid?
  end

  # ─── Méthodes XP : xp_for_next_level ────────────────────────────────────────

  # Cas nominal : au niveau 1, le prochain seuil est 100 XP.
  # update_columns contourne les validations pour forcer l'état en base.
  test "xp_for_next_level retourne 100 au niveau 1" do
    profil = create_user_with_profil
    profil.update_columns(xp_level: 1, xp: 0)
    # LEVEL_THRESHOLDS[1] = 100
    assert_equal 100, profil.xp_for_next_level
  end

  # Cas nominal : au niveau 3, le prochain seuil est 600 XP.
  test "xp_for_next_level retourne 600 au niveau 3" do
    profil = create_user_with_profil
    profil.update_columns(xp_level: 3, xp: 300)
    # LEVEL_THRESHOLDS[3] = 600
    assert_equal 600, profil.xp_for_next_level
  end

  # Edge case : au niveau max (10), retourne le dernier seuil (10_000).
  test "xp_for_next_level retourne le dernier seuil au niveau max" do
    profil = create_user_with_profil
    profil.update_columns(xp_level: 10, xp: 10_000)
    assert_equal 10_000, profil.xp_for_next_level
  end

  # ─── Méthodes XP : xp_for_current_level ────────────────────────────────────

  # Cas nominal : au niveau 1, le plancher est 0.
  test "xp_for_current_level retourne 0 au niveau 1" do
    profil = create_user_with_profil
    profil.update_columns(xp_level: 1)
    assert_equal 0, profil.xp_for_current_level
  end

  # Cas nominal : au niveau 2, le plancher est 100.
  test "xp_for_current_level retourne 100 au niveau 2" do
    profil = create_user_with_profil
    profil.update_columns(xp_level: 2, xp: 100)
    # LEVEL_THRESHOLDS[1] = 100
    assert_equal 100, profil.xp_for_current_level
  end

  # ─── Méthodes XP : xp_progress_percent ─────────────────────────────────────

  # Cas nominal : 0 XP au niveau 1 → 0% de progression.
  test "xp_progress_percent retourne 0 au début du niveau 1" do
    profil = create_user_with_profil
    profil.update_columns(xp_level: 1, xp: 0)
    assert_equal 0, profil.xp_progress_percent
  end

  # Cas nominal : 50 XP sur 100 (niveau 1→2) → 50%.
  test "xp_progress_percent retourne 50 à mi-chemin du niveau 1" do
    profil = create_user_with_profil
    profil.update_columns(xp_level: 1, xp: 50)
    # (50 - 0) / (100 - 0) * 100 = 50%
    assert_equal 50, profil.xp_progress_percent
  end

  # Edge case : niveau max → 100%.
  test "xp_progress_percent retourne 100 au niveau max" do
    profil = create_user_with_profil
    profil.update_columns(xp_level: 10, xp: 10_000)
    assert_equal 100, profil.xp_progress_percent
  end

  # ─── Méthode recalculate_level! ─────────────────────────────────────────────

  # Cas nominal : 150 XP → passage au niveau 2 (seuil 100).
  test "recalculate_level! passe au niveau 2 avec 150 XP" do
    profil = create_user_with_profil
    profil.update_columns(xp: 150, xp_level: 1, stat_points: 0)
    profil.recalculate_level!
    assert_equal 2, profil.reload.xp_level
  end

  # Cas nominal : le nombre de stat_points augmente de 3 par niveau gagné.
  # LEVEL_THRESHOLDS = [0, 100, 300, 600, 1000, ...]
  # 300 XP → rindex { |t| 300 >= t } = index 2 → new_level = 3
  # était niveau 1 → +2 niveaux = +6 stat_points
  test "recalculate_level! attribue 3 stat_points par niveau gagné" do
    profil = create_user_with_profil
    profil.update_columns(xp: 300, xp_level: 1, stat_points: 0)
    profil.recalculate_level!
    assert_equal 6, profil.reload.stat_points
  end

  # Cas d'erreur : si le niveau ne change pas, stat_points n'est pas modifié.
  test "recalculate_level! ne modifie pas stat_points si le niveau est inchangé" do
    profil = create_user_with_profil
    # 50 XP → reste niveau 1
    profil.update_columns(xp: 50, xp_level: 1, stat_points: 3)
    profil.recalculate_level!
    assert_equal 3, profil.reload.stat_points
  end

  # ─── Méthode level_badge_color ──────────────────────────────────────────────

  # Cas nominal : niveaux 1-4 → "success" (vert).
  test "level_badge_color retourne success pour niveau 1" do
    profil = create_user_with_profil
    profil.update_columns(xp_level: 1)
    assert_equal "success", profil.level_badge_color
  end

  test "level_badge_color retourne success pour niveau 4" do
    profil = create_user_with_profil
    profil.update_columns(xp_level: 4)
    assert_equal "success", profil.level_badge_color
  end

  # Cas nominal : niveaux 5-8 → "primary" (bleu).
  test "level_badge_color retourne primary pour niveau 5" do
    profil = create_user_with_profil
    profil.update_columns(xp_level: 5)
    assert_equal "primary", profil.level_badge_color
  end

  test "level_badge_color retourne primary pour niveau 8" do
    profil = create_user_with_profil
    profil.update_columns(xp_level: 8)
    assert_equal "primary", profil.level_badge_color
  end

  # Cas nominal : niveaux 9-10 → "warning" (or).
  test "level_badge_color retourne warning pour niveau 9" do
    profil = create_user_with_profil
    profil.update_columns(xp_level: 9)
    assert_equal "warning", profil.level_badge_color
  end

  test "level_badge_color retourne warning pour niveau 10" do
    profil = create_user_with_profil
    profil.update_columns(xp_level: 10)
    assert_equal "warning", profil.level_badge_color
  end

  # ─── Méthode card_tier_class ────────────────────────────────────────────────

  test "card_tier_class retourne card-tier-bronze pour niveau 1" do
    profil = create_user_with_profil
    profil.update_columns(xp_level: 1)
    assert_equal "card-tier-bronze", profil.card_tier_class
  end

  test "card_tier_class retourne card-tier-silver pour niveau 3" do
    profil = create_user_with_profil
    profil.update_columns(xp_level: 3)
    assert_equal "card-tier-silver", profil.card_tier_class
  end

  test "card_tier_class retourne card-tier-gold pour niveau 5" do
    profil = create_user_with_profil
    profil.update_columns(xp_level: 5)
    assert_equal "card-tier-gold", profil.card_tier_class
  end

  test "card_tier_class retourne card-tier-platinum pour niveau 7" do
    profil = create_user_with_profil
    profil.update_columns(xp_level: 7)
    assert_equal "card-tier-platinum", profil.card_tier_class
  end

  test "card_tier_class retourne card-tier-elite pour niveau 9" do
    profil = create_user_with_profil
    profil.update_columns(xp_level: 9)
    assert_equal "card-tier-elite", profil.card_tier_class
  end

  # ─── Méthode theme ──────────────────────────────────────────────────────────

  # Cas nominal : light_mode = false → thème "dark" (défaut de l'app).
  test "theme retourne dark si light_mode est false" do
    profil = create_user_with_profil
    profil.update_column(:light_mode, false)
    assert_equal "dark", profil.theme
  end

  # Cas nominal : light_mode = true → thème "light".
  test "theme retourne light si light_mode est true" do
    profil = create_user_with_profil
    profil.update_column(:light_mode, true)
    assert_equal "light", profil.theme
  end

  # ─── Méthode needs_onboarding_modal? ────────────────────────────────────────

  # Cas nominal : onboarding_shown_at est nil → la modale doit être affichée.
  test "needs_onboarding_modal? retourne vrai si onboarding_shown_at est nil" do
    profil = create_user_with_profil
    profil.update_column(:onboarding_shown_at, nil)
    assert profil.needs_onboarding_modal?
  end

  # Cas d'erreur : onboarding déjà montré → on ne le montre plus.
  test "needs_onboarding_modal? retourne faux si onboarding_shown_at est présent" do
    profil = create_user_with_profil
    profil.update_column(:onboarding_shown_at, Time.current)
    assert_not profil.needs_onboarding_modal?
  end

  # ─── Méthode needs_profile_reminder? ────────────────────────────────────────

  # Cas d'erreur : si preferred_city est présente, pas de reminder.
  test "needs_profile_reminder? retourne faux si preferred_city est présente" do
    profil = create_user_with_profil
    profil.update_columns(
      preferred_city:      "Paris",
      onboarding_shown_at: 10.days.ago,
      profile_reminder_dismissed_at: nil
    )
    assert_not profil.needs_profile_reminder?
  end

  # Cas d'erreur : si l'onboarding a été montré il y a moins de 7 jours, pas de reminder.
  test "needs_profile_reminder? retourne faux si onboarding < 7 jours" do
    profil = create_user_with_profil
    profil.update_columns(
      preferred_city:      nil,
      onboarding_shown_at: 3.days.ago,   # trop récent
      profile_reminder_dismissed_at: nil
    )
    assert_not profil.needs_profile_reminder?
  end

  # Cas d'erreur : si le reminder a déjà été fermé, on ne le réaffiche pas.
  test "needs_profile_reminder? retourne faux si reminder déjà fermé" do
    profil = create_user_with_profil
    profil.update_columns(
      preferred_city:               nil,
      onboarding_shown_at:          10.days.ago,
      profile_reminder_dismissed_at: 1.day.ago
    )
    assert_not profil.needs_profile_reminder?
  end

  # Cas nominal : toutes les conditions réunies → le reminder doit être affiché.
  test "needs_profile_reminder? retourne vrai si toutes les conditions sont remplies" do
    profil = create_user_with_profil
    profil.update_columns(
      preferred_city:               nil,
      onboarding_shown_at:          10.days.ago,  # > 7 jours
      profile_reminder_dismissed_at: nil           # pas encore fermé
    )
    assert profil.needs_profile_reminder?
  end
end
