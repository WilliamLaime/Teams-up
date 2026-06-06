# Concern qui branche la modération IA automatique sur un modèle qui possède
# un ou plusieurs attachements Active Storage.
#
# Usage :
#
#   class Profil < ApplicationRecord
#     include Moderatable
#     has_one_attached :avatar
#     moderated_attachments :avatar
#   end
#
#   class Team < ApplicationRecord
#     include Moderatable
#     has_one_attached :badge_image
#     has_one_attached :cover_image
#     moderated_attachments :badge_image, :cover_image
#   end
#
# Fonctionnement :
#
#   1. `moderated_attachments` enregistre la liste des noms d'attachements à
#      surveiller sur la classe et branche deux callbacks : un `before_save`
#      pour détecter les changements en attente, un `after_commit` pour
#      enfiler les jobs une fois que la sauvegarde a réussi.
#
#   2. Dans `before_save`, on lit `attachment_changes` (API standard Active
#      Storage). Ce hash contient les modifications d'attachements encore
#      non appliquées — c'est le seul endroit fiable pour savoir quel
#      attachement est en train d'être ajouté ou remplacé, parce qu'après
#      commit l'information est perdue et on ne peut plus distinguer un
#      upload tout neuf d'un attachement déjà modéré.
#
#   3. Dans `after_commit`, pour chaque attachement qui était en changement
#      ET qui est toujours attaché (on filtre les détachements volontaires
#      par l'utilisateur), on enfile un `ModerateImageJob`. Le job se charge
#      du reste (download + appel API + verdict + purge éventuelle).
#
# Prévention de la boucle infinie :
#
#   Quand le Checker détecte une image NSFW, il appelle `attachment.purge_later`.
#   Cette purge supprime la ligne ActiveStorage::Attachment en base mais ne
#   déclenche PAS d'after_commit sur le record parent (has_one_attached ne
#   touche pas la timestamp du record). Donc en théorie, la boucle n'existe
#   même pas. Mais on garde le flag THREAD_SKIP_KEY en ceinture-et-bretelles
#   au cas où un futur changement de Rails ou une purge synchrone modifierait
#   ce comportement.
module Moderatable
  extend ActiveSupport::Concern

  class_methods do
    # DSL déclaratif. Accepte une liste de noms d'attachements symboles ou
    # strings. La liste est stockée sur la classe (pas sur l'instance) parce
    # qu'elle est constante pour tous les objets de la classe.
    def moderated_attachments(*names)
      @_moderated_attachment_names = names.map(&:to_s).freeze

      before_save  :_capture_moderatable_changes
      after_commit :_enqueue_moderatable_jobs
    end

    # Liste des noms d'attachements modérés pour cette classe. Utilisé par
    # les callbacks. Défaut à tableau vide gelé si aucun n'a été déclaré
    # (par exemple si le concern est inclus mais jamais configuré).
    def _moderated_attachment_names
      @_moderated_attachment_names ||= [].freeze
    end
  end

  private

  # Avant la sauvegarde, on note quels attachements modérés ont une
  # modification en attente. `attachment_changes` retourne un hash dont les
  # clés sont les noms d'attachements et les valeurs des objets
  # ActiveStorage::Attached::Changes::CreateOne (ou DeleteOne). La simple
  # présence d'une clé signifie qu'il y a un changement — on filtrera plus
  # tard les détachements en vérifiant que l'attachement est toujours attaché
  # après le commit.
  def _capture_moderatable_changes
    @_pending_moderatable_changes = self.class._moderated_attachment_names.select do |name|
      attachment_changes[name].present?
    end
  end

  # Après commit, pour chaque attachement marqué comme changé ET toujours
  # attaché, on enfile un job de modération. Le filtre "toujours attaché"
  # ignore les détachements volontaires : l'utilisateur qui supprime son
  # avatar n'a rien à modérer.
  #
  # Si on est dans une opération déclenchée par le Checker (purge après
  # rejet NSFW), on court-circuite pour éviter toute boucle — ceinture et
  # bretelles, voir le commentaire d'en-tête du module.
  def _enqueue_moderatable_jobs
    return if Thread.current[ImageModeration::Checker::THREAD_SKIP_KEY]

    pending = @_pending_moderatable_changes
    return if pending.blank?

    pending.each do |name|
      next unless public_send(name).attached?

      ModerateImageJob.perform_later(self, name)
    end
  ensure
    @_pending_moderatable_changes = nil
  end
end
