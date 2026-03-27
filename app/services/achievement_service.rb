# Service qui gère l'attribution des achievements et de l'XP
# Utilisé par les controllers après chaque action importante
#
# Exemple d'utilisation :
#   AchievementService.new(current_user).check(:first_join)
class AchievementService
  def initialize(user)
    @user   = user
    @profil = user.profil
  end

  # Point d'entrée principal — reçoit un trigger et vérifie les achievements correspondants
  # @param trigger [Symbol] — :first_join, :match_joined, :message_sent, :match_created, :profile_updated
  def check(trigger)
    # Si le profil n'existe pas encore, on ne fait rien
    return unless @profil

    case trigger
    when :first_join       then check_first_join
    when :match_joined     then check_match_count
    when :message_sent     then check_message_count
    when :match_created    then check_match_created
    when :profile_updated  then check_profile_complete
    end
  end

  private

  # ─── VÉRIFICATIONS PAR TRIGGER ─────────────────────────────────────────────

  # Vérifie si c'est la toute première inscription à un match
  def check_first_join
    # Compte les matchs où l'utilisateur est joueur approuvé
    joined_count = @user.match_users.where(role: "joueur", status: "approved").count
    grant("first_join") if joined_count >= 1
  end

  # Vérifie les achievements liés au nombre de matchs joués
  def check_match_count
    joined_count = @user.match_users.where(role: "joueur", status: "approved").count
    grant("matches_5")  if joined_count >= 5
    grant("matches_10") if joined_count >= 10
    grant("matches_25") if joined_count >= 25   # Légende du terrain
    grant("matches_50") if joined_count >= 50   # Roi des terrains
  end

  # Vérifie les achievements liés aux messages envoyés
  def check_message_count
    message_count = Message.where(user: @user).count
    grant("first_message") if message_count >= 1
    grant("messages_10")   if message_count >= 10
    grant("messages_50")   if message_count >= 50 # Voix du stade
  end

  # Vérifie les achievements liés à la création de matchs
  def check_match_created
    # Compte les matchs où l'utilisateur est organisateur
    organized_count = @user.match_users.where(role: "organisateur").count
    grant("first_match_created") if organized_count >= 1
    grant("organized_3")         if organized_count >= 3
    grant("organized_10")        if organized_count >= 10 # Général des terrains
  end

  # Vérifie les achievements liés au profil (complétion + avatar + description)
  def check_profile_complete
    # Profil entièrement complété (avatar + description + téléphone)
    grant("profile_complete") if @profil.avatar.attached? && @profil.description.present? && @profil.phone.present?
    # Avatar ajouté
    grant("avatar_added")         if @profil.avatar.attached?
    # Description rédigée
    grant("description_written")  if @profil.description.present?
  end

  # ─── ATTRIBUTION D'UN ACHIEVEMENT ─────────────────────────────────────────

  # Attribue un achievement à l'utilisateur s'il ne l'a pas déjà
  # @param achievement_key [String] — la clé unique de l'achievement
  def grant(achievement_key)
    achievement = Achievement.find_by(key: achievement_key)
    # Achievement introuvable en base (seeds pas encore lancés ?)
    return unless achievement
    # Déjà débloqué — on ne double pas les récompenses
    return if @user.user_achievements.exists?(achievement: achievement)

    # Créer l'entrée UserAchievement
    @user.user_achievements.create!(achievement: achievement)
    # Ajouter l'XP au profil
    award_xp(achievement.xp_reward)
    # Envoyer une notification en temps réel
    send_notification(achievement)
  end

  # Ajoute de l'XP au profil, recalcule le niveau, puis broadcast la mise à jour.
  # broadcast_xp_update est appelé EN DERNIER pour que xp_level soit déjà à jour.
  def award_xp(amount)
    @profil.increment!(:xp, amount)
    @profil.recalculate_level!
    @profil.broadcast_xp_update
  end

  # Crée une notification pour informer l'utilisateur de son achievement
  def send_notification(achievement)
    Notification.create!(
      user: @user,
      message: "🏆 Achievement débloqué : #{achievement.name} (+#{achievement.xp_reward} XP)",
      link: "/profil"
    )
  end
end
