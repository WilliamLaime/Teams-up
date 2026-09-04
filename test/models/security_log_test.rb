require "test_helper"

# Tests du modèle SecurityLog.
# Ce modèle enregistre les événements de sécurité de l'application.
# On vérifie : la validation event_type, les scopes, et la méthode de classe .log.
class SecurityLogTest < ActiveSupport::TestCase
  # Désactive la parallélisation — les tests partagent des données en base
  # et on appelle teardown_db manuellement pour contrôler l'ordre de suppression.
  parallelize(workers: 1)

  teardown { teardown_db }

  # ─── Helper ─────────────────────────────────────────────────────────────────

  # Retourne un hash valide pour créer un SecurityLog (sans passer par .log)
  def valid_attrs(overrides = {})
    { event_type: "login_success", ip_address: "127.0.0.1" }.merge(overrides)
  end

  # ─── Validation : event_type ─────────────────────────────────────────────────

  # Cas nominal : un event_type dans la liste EVENT_TYPES est valide.
  test "event_type valide est accepté" do
    log = SecurityLog.new(valid_attrs)
    assert log.valid?, "Attendu valide, erreurs : #{log.errors.full_messages}"
  end

  # Cas d'erreur : un event_type hors de la liste est refusé.
  test "event_type invalide rend le log invalide" do
    log = SecurityLog.new(valid_attrs(event_type: "inconnu"))
    assert log.invalid?
    assert log.errors[:event_type].any?
  end

  # Vérifie que tous les types de la constante EVENT_TYPES sont acceptés.
  # Si quelqu'un ajoute un type à la constante, ce test continuera de passer.
  test "tous les EVENT_TYPES sont valides" do
    SecurityLog::EVENT_TYPES.each do |type|
      log = SecurityLog.new(valid_attrs(event_type: type))
      assert log.valid?, "event_type '#{type}' devrait être valide"
    end
  end

  # ─── Constante EVENT_TYPES ───────────────────────────────────────────────────

  # Vérifie que les types clés attendus sont présents dans la constante.
  test "EVENT_TYPES contient les types essentiels" do
    %w[login_success login_failure signup password_reset_request].each do |type|
      assert_includes SecurityLog::EVENT_TYPES, type,
                      "'#{type}' devrait être dans EVENT_TYPES"
    end
  end

  # ─── Scope : recent ──────────────────────────────────────────────────────────

  # Cas nominal : le scope recent trie du plus récent au plus ancien.
  test "scope recent trie par created_at desc" do
    # Crée deux logs avec des timestamps distincts
    first = SecurityLog.create!(valid_attrs.merge(created_at: 2.hours.ago))
    second = SecurityLog.create!(valid_attrs.merge(created_at: 1.hour.ago))

    # Le premier résultat du scope recent doit être le plus récent
    result = SecurityLog.recent
    assert_equal second.id, result.first.id,
                 "recent doit retourner d'abord le log le plus récent"
    assert_equal first.id, result.last.id
  end

  # ─── Scope : by_type ─────────────────────────────────────────────────────────

  # Cas nominal : by_type filtre correctement par event_type.
  test "scope by_type filtre par event_type" do
    SecurityLog.create!(valid_attrs(event_type: "login_success"))
    SecurityLog.create!(valid_attrs(event_type: "signup"))

    result = SecurityLog.by_type("login_success")
    assert result.all? { |l| l.event_type == "login_success" },
           "by_type('login_success') ne doit retourner que des logs de ce type"
  end

  # ─── Méthode de classe .log ───────────────────────────────────────────────────

  # Cas nominal : .log crée un SecurityLog en base avec les bonnes valeurs.
  test ".log crée un SecurityLog avec l'IP et le détail" do
    # On simule un objet request minimal (duck-typing)
    fake_request = OpenStruct.new(remote_ip: "192.168.1.1", user_agent: "TestAgent/1.0")

    assert_difference "SecurityLog.count", 1 do
      SecurityLog.log("login_success", fake_request, email: "test@example.com")
    end

    log = SecurityLog.last
    assert_equal "login_success",  log.event_type
    assert_equal "192.168.1.1",    log.ip_address
    assert_equal "TestAgent/1.0",  log.user_agent
  end

  # Cas nominal : .log accepte un utilisateur en keyword argument.
  test ".log accepte un user en keyword argument" do
    user = create_test_user(email: "loguser@example.com", first_name: "Log", last_name: "User")
    fake_request = OpenStruct.new(remote_ip: "10.0.0.1", user_agent: nil)

    SecurityLog.log("login_success", fake_request, user: user)

    log = SecurityLog.last
    assert_equal user.id, log.user_id, ".log doit associer le user passé en argument"
  end

  # Cas de robustesse : .log ne lève pas d'exception si event_type est invalide —
  # il rescue l'erreur et écrit dans le logger pour ne pas interrompre l'action principale.
  test ".log ne lève pas d'exception si event_type est invalide" do
    fake_request = OpenStruct.new(remote_ip: "1.2.3.4", user_agent: nil)

    # Ne doit pas lever d'exception même avec un type inconnu
    assert_nothing_raised do
      SecurityLog.log("type_inexistant", fake_request)
    end
  end

  # ─── Association ─────────────────────────────────────────────────────────────

  # Cas nominal : un SecurityLog peut exister sans user (belongs_to optional: true).
  test "log sans user est valide (belongs_to optional)" do
    log = SecurityLog.new(valid_attrs)
    assert log.valid?, "Un log sans user doit être valide car belongs_to est optional"
  end

  # ─── Rétention RGPD ──────────────────────────────────────────────────────────
  # Un SecurityLog contient une IP et un user-agent : la durée de conservation
  # doit être appliquée (rake security_logs:purge). Voir docs/SECURITE-RGPD.md.

  test "purgeable ne retient que les logs plus vieux que la rétention" do
    recent = SecurityLog.create!(valid_attrs)
    old    = SecurityLog.create!(valid_attrs)
    old.update_column(:created_at, SecurityLog::RETENTION_PERIOD.ago - 1.day)

    purgeable_ids = SecurityLog.purgeable.pluck(:id)
    assert_includes purgeable_ids, old.id
    refute_includes purgeable_ids, recent.id
  end

  test "purgeable accepte une durée personnalisée" do
    log = SecurityLog.create!(valid_attrs)
    log.update_column(:created_at, 2.months.ago)

    assert_includes SecurityLog.purgeable(1.month).pluck(:id), log.id
    refute_includes SecurityLog.purgeable(6.months).pluck(:id), log.id
  end
end
