# Persiste un match déjà construit puis applique les effets de bord communs à
# TOUTE création de match, quel que soit le canal (formulaire web ou slash Slack) :
#   1. sauvegarde du match ;
#   2. inscription du créateur comme organisateur approuvé ;
#   3. planification du rappel ~24 h avant le coup d'envoi.
#
# Ce qui reste PROPRE à chaque appelant (et n'entre donc PAS ici) : la restriction
# de genre (dépend du canal), l'invitation d'équipe, le rattachement tournoi, l'email
# de confirmation, le Web Push et le partage Slack. Le controller web les orchestre
# autour de ce service ; la modale Slack, elle, n'en a pas besoin.
class MatchCreationService
  # `saved` porte le résultat du save ; `success?` en est l'alias lisible.
  Result = Struct.new(:match, :saved) do
    def success?
      saved
    end
  end

  # @param match [Match] instance déjà construite (attributs + user affectés)
  def initialize(match:)
    @match = match
  end

  def call
    if @match.save
      # Le créateur devient organisateur approuvé (même rôle que via le web).
      @match.match_users.create(user: @match.user, role: "organisateur", status: "approved")
      schedule_reminder
    end

    Result.new(match: @match, saved: @match.persisted?)
  end

  private

  # Planifie le rappel ~24 h avant le match (anticipé de 30 min pour absorber un
  # retard de la queue). Le job revérifie que le match n'a pas commencé avant d'envoyer.
  def schedule_reminder
    reminder_time = @match.build_datetime - 24.5.hours
    return unless reminder_time > Time.current

    MatchReminderJob.set(wait_until: reminder_time).perform_later(@match.id)
  end
end
