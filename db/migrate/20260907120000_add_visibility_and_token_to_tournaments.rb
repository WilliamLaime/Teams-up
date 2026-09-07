# ── Mode privé d'un tournoi ───────────────────────────────────────────────────
# Décalque exact du mode privé des matchs (cf.
# 20260319151235_add_visibility_and_token_to_matches) : un tournoi privé
# n'apparaît ni sur /tournois ni dans la recherche, et ne s'ouvre que par son
# lien à token — l'organisation et les inscrits y accèdent toujours sans token.
#
# `default: "public", null: false` : les tournois existants sont rétro-remplis en
# public, donc rien ne change pour eux. Le token, lui, reste nullable : il n'est
# généré que si le tournoi passe en privé (Tournament#generate_private_token).
class AddVisibilityAndTokenToTournaments < ActiveRecord::Migration[8.1]
  def change
    add_column :tournaments, :visibility, :string, default: "public", null: false
    add_column :tournaments, :private_token, :string
    add_index  :tournaments, :private_token, unique: true
  end
end
