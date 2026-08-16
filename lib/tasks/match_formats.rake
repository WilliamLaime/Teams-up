# Réalignement one-shot des formats de match incohérents avec leur sport.
#
# Pourquoi cette tâche existe : jusqu'ici rien ne liait `matches.format` au sport
# du match. Un match créé en volley ("3v3") puis repassé en ping-pong gardait son
# "3v3", et le champ caché du formulaire tournoi le réémettait à chaque édition.
# Conséquences visibles : "3v3" affiché sur une rencontre de ping-pong 1v1, et
# 4 joueurs "sur place" fantômes (Match#format_total déduit 6 joueurs de "3v3").
#
# Depuis, `Match#format_valid_for_sport` refuse ces valeurs — cette tâche nettoie
# donc aussi les matchs existants, qui sinon deviendraient inéditables.
#
# Le format de remplacement est le premier format à taille chiffrée du sport
# ("1v1" en ping-pong), soit exactement la règle appliquée en contexte tournoi
# (MatchesController#tournament_match_format). "Libre" est écarté : il rendrait
# `players_present` obligatoire alors qu'il n'est pas saisi ici.
#
# Utilisation :
#   rake match_formats:realign            # corrige
#   rake match_formats:realign DRY_RUN=1  # liste sans écrire
namespace :match_formats do
  desc "Réaligne matches.format sur les formats disponibles du sport (ex: 3v3 → 1v1 en ping-pong)"
  task realign: :environment do
    dry_run = ENV["DRY_RUN"].present?
    fixed   = 0
    cleared = 0

    Match.where.not(format: [nil, ""]).includes(:sport).find_each do |match|
      sport = match.sport
      next if sport.blank?

      labels = sport.available_formats.map { |fmt| fmt[:label] }
      next if labels.include?(match.format)

      # Premier format à taille chiffrée du sport ; nil si le sport n'en propose
      # aucun (il ne reste alors que "Libre" → on vide plutôt que d'inventer).
      replacement = sport.available_formats.find { |fmt| fmt[:players].present? }&.dig(:label)

      puts "Match ##{match.id} (#{sport.name}) : #{match.format.inspect} → #{replacement.inspect}"
      next if dry_run

      # update_column : on écrit sans repasser par les validations, dont celle du
      # délai de 30 min qui rejetterait tout match déjà joué.
      match.update_column(:format, replacement)
      # Le total du ratio dérive du format → il faut recalculer les places restantes.
      match.recompute_player_left!

      replacement.nil? ? cleared += 1 : fixed += 1
    end

    puts dry_run ? "DRY_RUN — aucune écriture." : "#{fixed} format(s) réaligné(s), #{cleared} vidé(s)."
  end
end
