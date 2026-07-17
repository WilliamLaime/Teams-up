require "test_helper"

# Tests pour AchievementService
# Ce service attribue les achievements et l'XP à un utilisateur selon ses actions.
# ATTENTION : La gamification est actuellement suspendue (GAMIFICATION_PAUSED = true).
# Les tests vérifient le comportement réel du service :
#   - Quand la gamification est suspendue → rien ne se passe (cas actuel)
#   - Quand la gamification est active → les achievements sont attribués
#     (simulé en remplaçant temporairement la constante GAMIFICATION_PAUSED)
class AchievementServiceTest < ActiveSupport::TestCase
  # Désactive la parallélisation pour éviter les deadlocks PostgreSQL
  # lors du chargement des fixtures dans plusieurs processus simultanés.
  parallelize(workers: 1)

  teardown do
    # Nettoyage dans l'ordre FK pour éviter les violations de contraintes
    UserAchievement.delete_all
    Achievement.delete_all
    Notification.delete_all
    teardown_db
  end

  # Helper : remplace temporairement une constante dans un module/classe
  # pour simuler un changement de configuration sans modifier le code source.
  # La valeur originale est restaurée après le bloc, même en cas d'exception.
  # @param klass [Class/Module] la classe qui contient la constante
  # @param const_name [Symbol]  le nom de la constante (ex: :GAMIFICATION_PAUSED)
  # @param new_value  [Object]  la valeur temporaire
  def with_const(klass, const_name, new_value)
    original = klass.const_get(const_name)
    klass.send(:remove_const, const_name)
    klass.const_set(const_name, new_value)
    yield
  ensure
    # Restaure toujours la valeur originale, même si le bloc lève une exception
    klass.send(:remove_const, const_name) rescue nil
    klass.const_set(const_name, original)
  end

  # Helper : crée un Achievement en base
  # Les achievements doivent exister en base pour être attribués.
  # En production, ils sont créés via seeds.rb.
  def create_achievement(key:, name:, xp_reward: 10, category: "match")
    Achievement.create!(
      key:       key,
      name:      name,
      xp_reward: xp_reward,
      category:  category
    )
  end

  # Helper : crée un match futur lié à la fixture sport football
  # et l'inscription de l'user avec le rôle spécifié.
  def create_match_and_join(user:, role: "joueur", status: "approved", place: "Paris")
    future_date = 2.hours.from_now
    organizer   = create_test_user(email: "orga_#{SecureRandom.hex(4)}@ach.com",
                                   first_name: "Orga", last_name: "Ach")
    match = Match.new(
      user:        organizer,
      sport:       sports(:one),   # Fixture Football — évite les violations d'unicité
      title:       "Match #{SecureRandom.hex(4)}",
      date:        future_date.to_date,
      time:        future_date.strftime("%H:%M"),
      players_needed: 5,
      level:       "Tout niveau",
      place:       place,
      visibility:  "public"
    )
    match.save!(validate: false)
    MatchUser.create!(match: match, user: user, status: status, role: role)
    match
  end

  # CAS : GAMIFICATION SUSPENDUE (état actuel du code)
  # Vérifie que le service ne fait absolument rien quand GAMIFICATION_PAUSED = true.
  test "ne fait rien si GAMIFICATION_PAUSED est true" do
    user = create_test_user(email: "gamif@test.com", first_name: "Gamif", last_name: "Test")
    create_achievement(key: "first_join", name: "Premier match")

    # S'assure que la constante est bien à true (état actuel)
    assert AchievementService::GAMIFICATION_PAUSED,
           "GAMIFICATION_PAUSED doit être true dans cet état du code"

    AchievementService.new(user).check(:first_join)

    # Aucun achievement ne doit avoir été attribué
    assert_equal 0, user.user_achievements.count,
                 "Aucun achievement ne doit être attribué quand la gamification est suspendue"
  end

  # CAS ACTIF : check(:first_join) attribue first_join
  # Vérifie que le service attribue l'achievement "first_join"
  # quand l'utilisateur a au moins 1 match approuvé avec le rôle "joueur".
  # On simule la gamification active via with_const.
  test "check first_join attribue first_join si l user a un match approuve" do
    user        = create_test_user(email: "first@test.com", first_name: "First", last_name: "Join")
    achievement = create_achievement(key: "first_join", name: "Premier match !")
    create_match_and_join(user: user, role: "joueur", status: "approved")

    # Simule GAMIFICATION_PAUSED = false pour tester la logique réelle du service
    with_const(AchievementService, :GAMIFICATION_PAUSED, false) do
      AchievementService.new(user).check(:first_join)
    end

    assert user.user_achievements.exists?(achievement: achievement),
           "L'achievement first_join doit être attribué"
  end

  # CAS DOUBLON : un achievement déjà débloqué n'est pas re-attribué.
  # La contrainte unique (user_id, achievement_id) en base garantit l'unicité.
  test "ne double pas un achievement deja attribue" do
    user        = create_test_user(email: "nodbl@test.com", first_name: "No", last_name: "Double")
    achievement = create_achievement(key: "first_join", name: "Premier match !")
    create_match_and_join(user: user, role: "joueur", status: "approved")

    with_const(AchievementService, :GAMIFICATION_PAUSED, false) do
      service = AchievementService.new(user)
      # Appel 1 → doit créer l'UserAchievement
      service.check(:first_join)
      # Appel 2 → ne doit pas créer de doublon
      service.check(:first_join)
    end

    # Il ne doit y avoir qu'une seule entrée UserAchievement pour cet achievement
    assert_equal 1, user.user_achievements.where(achievement: achievement).count,
                 "L'achievement ne doit être attribué qu'une seule fois"
  end

  # CAS ABSENT : achievement introuvable en base
  # Le service doit retourner nil silencieusement si l'achievement n'existe pas.
  # Cas typique : seeds pas encore lancés, ou clé inconnue.
  test "ne plante pas si l achievement n existe pas en base" do
    user = create_test_user(email: "noach@test.com", first_name: "No", last_name: "Ach")

    # Aucun achievement créé → grant() doit retourner nil silencieusement
    with_const(AchievementService, :GAMIFICATION_PAUSED, false) do
      assert_nothing_raised do
        AchievementService.new(user).check(:first_join)
      end
    end

    assert_equal 0, user.user_achievements.count
  end

  # CAS PROFIL ABSENT : user sans profil
  # Vérifie que le service ne plante pas si l'utilisateur n'a pas de profil.
  test "ne plante pas si l user n a pas de profil" do
    # Crée un user sans profil (bypass du helper create_test_user qui crée le profil)
    user = User.create!(
      email:        "noprofil@test.com",
      password:     "Test1234!",
      confirmed_at: Time.current,
      first_name:   "No",
      last_name:    "Profil"
    )
    # Pas d'appel à create_profil! → profil est nil

    with_const(AchievementService, :GAMIFICATION_PAUSED, false) do
      assert_nothing_raised do
        AchievementService.new(user).check(:first_join)
      end
    end

    assert_equal 0, user.user_achievements.count

    # Nettoyage manuel de l'user sans profil (hors du circuit normal de teardown_db)
    user.destroy
  end

  # CAS check(:match_created) : attribue first_match_created à l'organisateur
  # Vérifie que le service attribue l'achievement quand l'user a organisé au moins 1 match.
  test "check match_created attribue first_match_created si l user est organisateur" do
    user        = create_test_user(email: "orga_ach@test.com", first_name: "Orga", last_name: "Ach")
    achievement = create_achievement(key: "first_match_created", name: "Premier match organisé !")
    # L'organisateur a le rôle "organisateur" dans match_users
    create_match_and_join(user: user, role: "organisateur", status: "approved")

    with_const(AchievementService, :GAMIFICATION_PAUSED, false) do
      AchievementService.new(user).check(:match_created)
    end

    assert user.user_achievements.exists?(achievement: achievement),
           "L'achievement first_match_created doit être attribué à l'organisateur"
  end
end
