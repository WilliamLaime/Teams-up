class Message < ApplicationRecord
  # Un message appartient à un utilisateur (l'expéditeur)
  belongs_to :user

  # Un message appartient à un match (la conversation de groupe)
  belongs_to :match

  # Validation : le contenu est obligatoire et limité à 1000 caractères
  validates :content, presence: true, length: { maximum: 1000 }

  # Après la création d'un message, on le diffuse en temps réel
  # via Turbo Streams sur le stream spécifique au match
  # Cela met à jour la liste des messages sur toutes les pages ouvertes
  after_create_commit :broadcast_message

  private

  def broadcast_message
    # Diffuse le nouveau message en l'ajoutant à la fin de la liste (#chat-messages)
    # Tous les abonnés au stream "match_chat_<id>" le reçoivent instantanément
    broadcast_append_to(
      "match_chat_#{match_id}",   # nom du stream (unique par match)
      target: "chat-messages",    # l'élément HTML où ajouter le message
      partial: "messages/message",  # la vue partielle à rendre
      locals: { message: self }   # on passe le message à la partielle
    )
  end
end
