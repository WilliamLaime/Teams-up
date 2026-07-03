class AddPlayersNeededToMatches < ActiveRecord::Migration[8.1]
  # Introduit `players_needed` : la capacité cible IMMUABLE d'un match
  # (nombre de joueurs recherchés via l'app, hors organisateur).
  #
  # Jusqu'ici `player_left` servait à la fois de cible et de compteur décrémenté
  # à la main → il dérivait. Désormais `player_left` (places restantes) est DÉRIVÉ
  # de `players_needed` moins les joueurs confirmés, recalculé par un callback.
  #
  # On backfill `players_needed` en reconstruisant la cible d'origine
  # (places restantes actuelles + joueurs déjà confirmés), puis on resynchronise
  # `player_left` pour corriger d'un coup toutes les dérives existantes.
  def up
    add_column :matches, :players_needed, :integer

    # Backfill : cible = player_left actuel + joueurs approuvés hors organisateur
    execute <<~SQL.squish
      UPDATE matches
      SET players_needed = COALESCE(matches.player_left, 0) + (
        SELECT COUNT(*)
        FROM match_users
        WHERE match_users.match_id = matches.id
          AND match_users.status = 'approved'
          AND match_users.role IS DISTINCT FROM 'organisateur'
      )
    SQL

    # Resynchronise player_left = cible - confirmés (borné à 0) → purge les dérives
    execute <<~SQL.squish
      UPDATE matches
      SET player_left = GREATEST(
        COALESCE(matches.players_needed, 0) - (
          SELECT COUNT(*)
          FROM match_users
          WHERE match_users.match_id = matches.id
            AND match_users.status = 'approved'
            AND match_users.role IS DISTINCT FROM 'organisateur'
        ),
        0
      )
    SQL
  end

  def down
    remove_column :matches, :players_needed
  end
end
