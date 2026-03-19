class Profil < ApplicationRecord
  belongs_to :user

  # Prénom et nom sont obligatoires
  validates :first_name, presence: { message: "Le prénom est obligatoire" }
  validates :last_name, presence: { message: "Le nom est obligatoire" }

  # Active Storage — permet d'attacher une photo de profil
  # La photo est stockée sur Cloudinary (configuré dans config/storage.yml)
  has_one_attached :avatar

  # ─── SYSTÈME XP & NIVEAUX ───────────────────────────────────────────────────
  # Seuils d'XP cumulés pour atteindre chaque niveau
  # Index 0 = Niveau 1 (0 XP), Index 1 = Niveau 2 (100 XP), etc.
  LEVEL_THRESHOLDS = [0, 100, 300, 600, 1000, 1500, 2500, 4000, 6000, 10000].freeze

  # ─── ATTRIBUTS RPG ──────────────────────────────────────────────────────────
  # Les 8 attributs sur lesquels le joueur peut dépenser ses points de stats
  # 4 originaux (orientés sport collectif) + 4 universels (tous les sports)
  # Utilisé pour valider les paramètres dans le controller (sécurité)
  STAT_ATTRIBUTES = %w[
    attr_attack attr_defense attr_speed attr_precision
    attr_endurance attr_tactics attr_teamwork attr_mental
  ].freeze

  # XP nécessaire pour atteindre le niveau SUIVANT (plafond de progression)
  def xp_for_next_level
    # Si niveau max atteint, retourner le dernier seuil
    LEVEL_THRESHOLDS[xp_level] || LEVEL_THRESHOLDS.last
  end

  # XP de départ du niveau actuel (plancher de progression)
  def xp_for_current_level
    LEVEL_THRESHOLDS[(xp_level || 1) - 1] || 0
  end

  # Pourcentage de progression dans le niveau actuel (0..100)
  # Utilisé pour la barre de progression Bootstrap
  def xp_progress_percent
    range = xp_for_next_level - xp_for_current_level
    return 100 if range <= 0  # Niveau max atteint

    current_progress = (xp || 0) - xp_for_current_level
    [(current_progress.to_f / range * 100).round, 100].min
  end

  # Recalcule et sauvegarde le niveau selon l'XP actuel
  # Si le niveau augmente, accorde 3 points de stats par niveau gagné
  # Appelé après chaque attribution d'XP
  def recalculate_level!
    current_xp  = xp || 0
    old_level   = xp_level || 1
    # Trouver le dernier seuil que l'XP actuel dépasse (rindex = dernier index)
    new_level   = LEVEL_THRESHOLDS.rindex { |threshold| current_xp >= threshold }.to_i + 1

    if new_level > old_level
      # Le joueur a monté de niveau — on lui accorde 3 points par niveau gagné
      levels_gained = new_level - old_level
      increment!(:stat_points, levels_gained * 3)
    end

    update_column(:xp_level, new_level) if new_level != old_level
  end

  # Couleur Bootstrap du badge niveau selon la plage
  # Niveaux 1-4 : vert, 5-8 : bleu, 9-10 : or
  def level_badge_color
    lvl = xp_level || 1
    if lvl >= 9
      "warning"    # Or pour les niveaux élite
    elsif lvl >= 5
      "primary"    # Bleu pour les niveaux intermédiaires
    else
      "success"    # Vert pour les niveaux débutants
    end
  end

  # Classe CSS du tier de la carte — détermine les ornements du contour
  # Niveaux 1-2 : bronze, 3-4 : silver, 5-6 : or, 7-8 : platine, 9-10 : élite
  def card_tier_class
    lvl = xp_level || 1
    if    lvl >= 9 then "card-tier-elite"
    elsif lvl >= 7 then "card-tier-platinum"
    elsif lvl >= 5 then "card-tier-gold"
    elsif lvl >= 3 then "card-tier-silver"
    else                 "card-tier-bronze"
    end
  end
end
