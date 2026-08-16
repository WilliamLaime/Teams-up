# ── Seed d'un tournoi de démo complet (dev / local uniquement) ────────────────
#
# Crée un tournoi, y inscrit N joueurs de démo, le lance, puis SAISIT DE VRAIS
# SCORES match par match — exactement comme le ferait un organisateur dans l'UI :
# on passe par TournamentMatch#assign_score (le vainqueur est dérivé du score) et
# par TournamentEngine (qui recalcule le classement et génère la ronde suivante).
# Aucun état n'est écrit « à la main » : le tournoi obtenu est donc cohérent.
#
# Usage :
#   rails tournament:seed                          # 40 joueurs, tennis, ronde suisse, finale à jouer
#   PLAYERS=32 FORMAT=poules rails tournament:seed  # autre effectif / format
#   PROGRESS=full rails tournament:seed             # tournoi entièrement terminé (champion désigné)
#   PROGRESS=round_robin rails tournament:seed      # phase de groupes finie, tableau final vierge
#
# Variables d'environnement :
#   PLAYERS   nombre de joueurs inscrits            (défaut 40)
#   FORMAT    ronde_suisse | poules | championnat   (défaut ronde_suisse)
#   SPORT     slug du sport                          (défaut tennis)
#   ORGANIZER email de l'organisateur                (défaut : premier compte non-démo)
#   NAME      nom du tournoi                         (défaut « Démo <format> <PLAYERS> joueurs »)
#   PROGRESS  final | full | round_robin             (défaut final)
#   RESET     1 pour recréer le tournoi s'il existe déjà (le supprime)
namespace :tournament do
  desc "Crée un tournoi de démo avec N joueurs et des matchs joués (ENV: PLAYERS, FORMAT, SPORT, PROGRESS, RESET)"
  task seed: :environment do
    abort "❌ Refusé en production." if Rails.env.production?

    players_count = Integer(ENV.fetch("PLAYERS", 40))
    format        = ENV.fetch("FORMAT", "ronde_suisse")
    progress      = ENV.fetch("PROGRESS", "final")
    sport_slug    = ENV.fetch("SPORT", "tennis")

    abort "❌ FORMAT invalide (#{Tournament::FORMATS.join(', ')})" unless Tournament::FORMATS.include?(format)
    abort "❌ PROGRESS invalide (final, full, round_robin)" unless %w[final full round_robin].include?(progress)

    sport = Sport.find_by(slug: sport_slug) || abort("❌ Sport « #{sport_slug} » introuvable (#{Sport.pluck(:slug).join(', ')})")
    name  = ENV.fetch("NAME", "Démo #{format.tr('_', ' ')} #{players_count} joueurs")

    organizer =
      if ENV["ORGANIZER"].present?
        User.find_by(email: ENV["ORGANIZER"]) || abort("❌ Aucun utilisateur avec l'email #{ENV['ORGANIZER']}")
      else
        User.where.not("email LIKE '%@teamup-demo.fr'").order(:id).first || User.order(:id).first
      end
    abort "❌ Aucun utilisateur en base : lance d'abord `rails db:seed`." if organizer.nil?

    # ── Tournoi ───────────────────────────────────────────────────────────────
    existing = Tournament.find_by(name: name)
    if existing
      if ENV["RESET"] == "1"
        puts "♻️  Suppression du tournoi existant « #{name} » (##{existing.id})…"
        existing.destroy!
      else
        abort "⚠️  Le tournoi « #{name} » existe déjà (/tournois/#{existing.slug}). " \
              "Relance avec RESET=1 pour le recréer, ou change NAME."
      end
    end

    tournament = Tournament.create!(
      name: name,
      sport: sport,
      user: organizer,
      format: format,
      max_players: players_count,
      playoffs: true,
      date: Date.current + 7,
      time: Time.zone.parse("10:00"),
      place: "Paris 15e — Complexe Sportif Démo",
      description: "Tournoi de démonstration généré par `rails tournament:seed` " \
                   "pour visualiser le tableau, le classement et l'avancement."
    )
    puts "🏆 Tournoi ##{tournament.id} « #{tournament.name} » créé (#{sport.name}, #{format})."

    # ── Joueurs de démo ───────────────────────────────────────────────────────
    # Emails stables (demo-joueur-N@teamup-demo.fr) : les comptes sont réutilisés
    # d'un seed à l'autre au lieu d'empiler des doublons en base.
    first_names = %w[Léa Hugo Marta Yanis Chloé Noah Inès Malik Jade Théo Sofia Enzo Nora Adam Lina Ruben Alba Milo Zoé Ilan]
    last_names  = %w[Bernard Moreau Lopez Nguyen Diallo Rossi Kowalski Silva Haddad Faure Petit Girard Marchand Roy Blanc]

    players = (1..players_count).map do |i|
      user = User.find_or_initialize_by(email: "demo-joueur-#{i}@teamup-demo.fr")
      first = first_names[(i - 1) % first_names.size]
      last  = last_names[(i - 1) % last_names.size]
      if user.new_record?
        user.assign_attributes(password: "Demo1234!", confirmed_at: Time.current,
                               first_name: first, last_name: last)
        user.save!
      end
      user.profil || user.create_profil!(first_name: first, last_name: last)
      user
    end

    players.each do |player|
      TournamentUser.find_or_create_by!(tournament: tournament, user: player) do |tu|
        tu.role   = "joueur"
        tu.status = "approved"
      end
    end
    puts "👥 #{players.size} joueurs inscrits (mot de passe : Demo1234!)."

    # ── Lancement (même chemin que TournamentsController#start) ────────────────
    ActiveRecord::Base.transaction do
      tournament.update!(status: "in_progress")
      TournamentEngine.for(tournament).next_round!
    end

    # ── Générateur de scores réalistes selon le sport ──────────────────────────
    rules  = sport.scoring_rules
    needed = rules[:mode] == :sets ? (rules[:best_of] / 2) + 1 : 1

    # Renvoie le détail set-par-set [[a, b], …] d'un match gagné par `winner_side`
    # (:a ou :b). Les écarts varient → set average / point average distincts, donc
    # un classement et un seeding réellement départagés.
    score_for = lambda do |winner_side|
      if rules[:mode] == :score
        # Sport collectif : un seul score final. Nul évité (le tableau final a
        # besoin d'un vainqueur), sauf si le sport l'autorise — 1 match sur 8.
        loser_goals = rand(0..3)
        if rules[:allow_draw] && rand(8).zero?
          [[loser_goals, loser_goals]]
        else
          winner_goals = loser_goals + rand(1..3)
          winner_side == :a ? [[winner_goals, loser_goals]] : [[loser_goals, winner_goals]]
        end
      else
        # Sport de raquette : `needed` sets nets remportés par le vainqueur
        # (écart ≥ 2 → toujours valide au regard de la règle win_by_two).
        Array.new(needed) do
          set = [rules[:target], rand(0..(rules[:target] - 2))]
          winner_side == :a ? set : set.reverse
        end
      end
    end

    # ── Boucle de jeu ─────────────────────────────────────────────────────────
    # Reproduit fidèlement TournamentMatchesController#update : score → sauvegarde
    # → recompute du classement → génération de la suite dès la ronde complète.
    engine        = TournamentEngine.for(tournament)
    played_rounds = 0
    last_round_id = nil

    loop do
      round = tournament.reload.current_round
      break if round.nil? || tournament.completed?
      # Garde-fou anti boucle infinie : le moteur n'a plus rien à générer.
      break if round.id == last_round_id

      last_round_id = round.id

      # Arrêts demandés par PROGRESS : on laisse la suite « à jouer » dans l'UI.
      break if progress == "round_robin" && round.phase == "bracket"

      if progress == "final" && round.phase == "bracket" && round.tournament_matches.one?
        puts "⏸  Finale laissée à jouer (PROGRESS=final)."
        break
      end

      round.tournament_matches.where(status: "pending", is_bye: false).find_each do |match|
        match.assign_score(score_for.call(rand(2).zero? ? :a : :b))
        match.save!
      end

      if %w[swiss league pool].include?(round.phase)
        engine.recompute_stats_for(round.phase, apply_state: round.phase == "swiss")
      end

      played_rounds += 1
      label = round.phase == "bracket" ? "tour #{round.number} du tableau final" : "#{round.phase} #{round.number}"
      puts "  ✓ #{label} — #{round.tournament_matches.count} match(s) joué(s)"

      engine.next_round! if round.reload.complete?
    end

    # ── Récapitulatif ─────────────────────────────────────────────────────────
    tournament.reload
    puts ""
    puts "✅ « #{tournament.name} » — statut : #{tournament.status}"
    puts "   Rondes générées : #{tournament.tournament_rounds.count} (#{played_rounds} jouée(s))"
    puts "   Matchs : #{tournament.tournament_matches.count} " \
         "(#{tournament.tournament_matches.where(status: 'completed').count} terminés)"
    puts "   Qualifiés : #{tournament.tournament_users.qualified.count} / " \
         "éliminés : #{tournament.tournament_users.eliminated.count}"
    puts "   Champion : #{tournament.champion&.display_name || '— (tournoi en cours)'}"
    puts ""
    puts "🔗 http://localhost:3000/tournois/#{tournament.slug}"
  end
end
