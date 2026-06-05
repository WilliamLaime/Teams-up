# Orchestrateur central de la modération d'images.
#
# Responsabilités :
#   1. Trouver (ou créer) la ligne ImageModeration correspondant au couple
#      (record, attachment_name)
#   2. Télécharger le binaire de l'attachement depuis le storage (Cloudinary)
#   3. Appeler l'adapter configuré pour obtenir un Result
#   4. Mettre à jour la ligne ImageModeration avec le verdict
#   5. Si NSFW → purger l'attachement + créer une Notification in-app pour l'owner
#   6. En cas d'erreur API ou quota dépassé → fail-open (image reste visible)
#
# Usage :
#   ImageModeration::Checker.call(profil, :avatar)
#   ImageModeration::Checker.call(team,   :badge_image)
#   ImageModeration::Checker.call(team,   :cover_image)
#
# Ce service est appelé depuis ModerateImageJob (async). Ne jamais l'appeler
# depuis un controller ou une vue en synchrone : un appel API prend ~1 à 3s
# et on ne veut pas bloquer le rendu.
class ImageModeration
  class Checker
    # Flag de thread-local posé pendant la purge déclenchée par le Checker.
    # Le concern Moderatable (Phase 2) lira ce flag et n'enfilera PAS de job
    # quand il voit un changement d'attachement causé par une purge Checker.
    # C'est la prévention de la boucle infinie purge → modération → purge.
    THREAD_SKIP_KEY = :skip_image_moderation_callback

    # Point d'entrée pratique pour les appelants.
    def self.call(record, attachment_name)
      new(record, attachment_name).call
    end

    def initialize(record, attachment_name)
      @record          = record
      @attachment_name = attachment_name.to_s
    end

    def call
      # Protection précoce : si le record n'a pas (ou plus) d'attachement, on
      # n'appelle pas l'API et on quitte silencieusement. Ça couvre le cas où
      # un user a supprimé son avatar entre l'enqueue du job et son exécution.
      return unless attachment_attached?

      # Si le quota mensuel est déjà consommé côté notre compteur local, on
      # évite même l'appel API (inutile, il renverrait QuotaExceededError) et
      # on marque directement en errored. Le dashboard admin a déjà été alerté
      # à 80%, ceci est le hard stop définitif.
      if quota_exhausted?
        mark_errored!("quota_exceeded_local")
        return
      end

      # Appel synchrone à l'adapter. Toutes les erreurs sont attrapées et
      # converties en statut `errored` (fail-open).
      result = analyze!
      apply_verdict!(result)
    rescue ImageModeration::QuotaExceededError => e
      # Le quota a été dépassé côté Sightengine (on n'avait pas encore mis à
      # jour notre compteur local, race condition possible en début de mois).
      # Pas de retry : on marque en errored et on log.
      Rails.logger.warn("[ImageModeration] Quota exceeded: #{e.message}")
      mark_errored!("quota_exceeded")
    rescue ImageModeration::Error => e
      # RateLimitError / ApiError : on laisse remonter l'exception pour que
      # ActiveJob retry le job avec backoff exponentiel. Si tous les retries
      # échouent, ActiveJob appelera finalement le bloc discard_on du Job qui
      # marquera en errored (voir ModerateImageJob).
      Rails.logger.warn("[ImageModeration] Adapter error: #{e.class}: #{e.message}")
      raise
    end

    private

    attr_reader :record, :attachment_name

    # Récupère la ligne ImageModeration existante ou en crée une nouvelle en
    # statut pending. L'index unique (type, id, attachment_name) garantit
    # qu'on a bien une seule ligne par couple.
    def moderation
      @moderation ||= ImageModeration.find_or_create_by!(
        moderatable: record,
        attachment_name: attachment_name
      ) do |m|
        m.status   = "pending"
        m.provider = adapter.provider_name
      end
    end

    # Instance de l'adapter configuré. Pour l'instant Sightengine en dur ; la
    # configuration plus fine (via Rails.application.config) viendra le jour où
    # on veut switcher en test ou en staging.
    def adapter
      @adapter ||= ImageModeration::Adapters::Sightengine.new
    end

    # Télécharge le binaire et appelle l'adapter.
    #
    # On utilise `blob.download` (qui retourne les bytes bruts) plutôt que
    # `blob.open` (qui fait passer par un Tempfile + vérification checksum MD5).
    # Raison : le gem Cloudinary re-encode parfois les images à l'upload
    # (auto-optimisation JPEG), ce qui change les bytes. La vérification
    # d'intégrité d'Active Storage compare alors le MD5 reçu au MD5 attendu
    # et lève ActiveStorage::IntegrityError. `blob.download` saute cette
    # vérification et convient parfaitement pour notre usage (on ne stocke
    # pas les bytes, on les envoie juste à l'API).
    #
    # StringIO enveloppe les bytes pour exposer l'API IO attendue par l'adapter.
    def analyze!
      blob  = attachment.blob
      bytes = blob.download
      adapter.analyze(StringIO.new(bytes), filename: blob.filename.to_s)
    end

    # Applique le verdict du Result à la ligne ImageModeration et déclenche
    # les actions dérivées (purge + notification si NSFW).
    def apply_verdict!(result)
      moderation.update!(
        status: result.nsfw? ? "rejected" : "approved",
        score: result.score,
        reason: result.nsfw? ? "nsfw_detected" : "safe",
        checked_at: Time.current
      )

      purge_and_notify! if result.nsfw?
    end

    # Purge l'attachement et notifie l'owner. Le flag THREAD_SKIP_KEY est posé
    # pendant la purge pour que le concern Moderatable (Phase 2) ignore le
    # callback après_commit déclenché par la suppression → pas de boucle.
    def purge_and_notify!
      Thread.current[THREAD_SKIP_KEY] = true
      attachment.purge_later
      notify_owner!
    ensure
      Thread.current[THREAD_SKIP_KEY] = false
    end

    # Crée une Notification in-app pour l'owner du record. Pour Profil, l'owner
    # est `profil.user`. Pour Team, c'est `team.captain`. Ton pédagogique avec
    # porte de sortie vers le support si faux positif.
    #
    # Note : le texte exact et les locales seront affinés en Phase 3. Ici on
    # pose une version v1 fonctionnelle pour que la chaîne soit testable de
    # bout en bout dès maintenant.
    def notify_owner!
      owner = notification_owner
      return unless owner

      Notification.create!(
        user: owner,
        notif_type: "image_rejected",
        message: notification_message,
        link: notification_link
      )
    end

    # Récupère l'utilisateur à notifier selon le type de record.
    def notification_owner
      case record
      when Profil then record.user
      when Team   then record.captain
      end
    end

    # Texte de la notification, varie selon l'attachement concerné. Les
    # messages sont centralisés dans config/locales/fr.yml sous la clé
    # `image_moderation.notifications.<attachment_name>` pour faciliter
    # l'ajustement du ton et une éventuelle traduction future.
    def notification_message
      I18n.t("image_moderation.notifications.#{attachment_name}")
    end

    # Lien vers la page où l'utilisateur peut réparer la situation.
    def notification_link
      case record
      when Profil then Rails.application.routes.url_helpers.edit_profil_path(record)
      when Team   then Rails.application.routes.url_helpers.edit_team_path(record)
      end
    rescue StandardError
      # Si les helpers de routes ne sont pas disponibles (tests isolés, etc.),
      # on tombe sur un lien nil — la notification reste utilisable.
      nil
    end

    # Passe la ligne de modération en errored avec une raison. Ne lève pas
    # d'exception, c'est la branche fail-open.
    def mark_errored!(reason)
      moderation.update!(
        status: "errored",
        reason: reason,
        checked_at: Time.current
      )
    end

    # Accès au ActiveStorage::Attached via le nom dynamique. Utilise
    # public_send parce que l'attachement est exposé comme une méthode
    # d'instance nommée d'après `has_one_attached`.
    def attachment
      record.public_send(attachment_name)
    end

    def attachment_attached?
      attachment.attached?
    end

    # Vrai si on a déjà atteint (ou dépassé) le quota mensuel Sightengine.
    # On ne lance plus d'appel API dans ce cas, c'est du gaspillage de jobs.
    def quota_exhausted?
      ImageModeration.quota_used_this_month >= ImageModeration::MONTHLY_QUOTA
    end
  end
end
