require "test_helper"

# Tests du modèle SportProfil.
# Un SportProfil est la table de jointure entre un Profil et un Sport.
# Il stocke le niveau du joueur pour ce sport.
# Validation custom : level_valid_for_sport
#   → si un niveau est renseigné, il doit appartenir à la grille officielle du sport
class SportProfilTest < ActiveSupport::TestCase
  teardown { teardown_db }

  # Crée un sport football avec le bon slug (icon non vide obligatoire).
  # Utilise un slug suffixamment unique pour éviter les conflits avec d'autres tests.
  def create_football
    # icon: "" est invalide (presence: true) → on passe un emoji réel
    # slug unique pour éviter les erreurs d'unicité si les tables ne sont pas nettoyées
    Sport.create!(name: "Football SP Test", slug: "football_sp_test_#{SecureRandom.hex(4)}", icon: "⚽")
  end

  # Crée un sport padel (grille différente).
  def create_padel
    Sport.create!(name: "Padel SP Test", slug: "padel_sp_test_#{SecureRandom.hex(4)}", icon: "🎾")
  end

  # Crée un utilisateur + profil
  def create_user_with_profil
    create_test_user(email: "sp_user@example.com", first_name: "SP", last_name: "User")
  end

  # ════════════════════════════════════════════════════════════════════════════
  # VALIDATION level_valid_for_sport
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un niveau valide pour le sport est accepté.
  # La grille football contient : Débutant, Intermédiaire, Avancé
  def test_level_valide_pour_le_sport
    user     = create_user_with_profil
    football = create_football
    sp = SportProfil.new(profil: user.profil, sport: football, level: "Débutant")
    # "Débutant" est dans la grille du football → valide
    assert sp.valid?, "Le niveau 'Débutant' est valide pour le football : #{sp.errors.full_messages}"
  end

  # Cas d'erreur : un niveau non reconnu pour ce sport est rejeté.
  # "Amateur" n'est PAS dans la grille football (Débutant, Intermédiaire, Avancé)
  def test_level_invalide_pour_le_sport
    user     = create_user_with_profil
    football = create_football
    # "Amateur" n'est pas dans la grille officielle du football
    sp = SportProfil.new(profil: user.profil, sport: football, level: "Amateur")
    refute sp.valid?, "Le niveau 'Amateur' ne doit pas être valide pour le football"
    assert sp.errors[:level].any?, "Une erreur sur :level doit être présente"
  end

  # Edge case : si le level est blank (nil ou ""), la validation est ignorée
  def test_level_blank_est_ignore_par_la_validation
    user    = create_user_with_profil
    football = create_football
    # Un joueur peut ne pas préciser son niveau → valide
    sp = SportProfil.new(profil: user.profil, sport: football, level: nil)
    assert sp.valid?, "Un SportProfil sans niveau doit être valide (niveau optionnel)"
  end

  # Edge case : un niveau vide string est aussi ignoré
  def test_level_vide_string_est_ignore
    user    = create_user_with_profil
    football = create_football
    sp = SportProfil.new(profil: user.profil, sport: football, level: "")
    assert sp.valid?, "Un SportProfil avec level vide doit être valide"
  end

  # Cas nominal : un niveau valide du padel est accepté
  def test_level_valide_pour_le_padel
    user  = create_user_with_profil
    padel = create_padel
    # "Débutant" est dans la grille officielle FFP
    sp = SportProfil.new(profil: user.profil, sport: padel, level: "Débutant")
    assert sp.valid?, "Le niveau 'Débutant' est valide pour le padel"
  end

  # Cas d'erreur : un niveau inexistant dans la grille du sport est rejeté
  # Les deux sports (football et padel) ont la même grille : Débutant, Intermédiaire, Avancé.
  # On teste qu'un niveau inventé ("NiveauInexistant") est toujours rejeté.
  def test_niveau_inexistant_est_invalide_pour_padel
    user  = create_user_with_profil
    padel = create_padel
    # "NiveauInexistant" n'est dans la grille d'aucun sport → invalide
    sp = SportProfil.new(profil: user.profil, sport: padel, level: "NiveauInexistant")
    refute sp.valid?, "Un niveau inexistant ne doit pas être valide pour le padel"
    assert sp.errors[:level].any?, "Une erreur sur :level doit être présente"
  end
end
