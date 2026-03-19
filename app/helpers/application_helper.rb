module ApplicationHelper
  # Génère un badge achievement avec le style exactement issu du Figma TeamUp :
  # — cercle plein (border-radius 9999px), fond rgba(255,255,255,0.05)
  # — glow blanc quand déverrouillé, grayscale + opacité réduite quand verrouillé
  # — emoji centré à 28px (adapté à la taille du badge dans l'armoire)
  def achievement_badge(achievement, is_unlocked:, size: 48)
    emoji      = achievement.icon_emoji.presence || "🏅"
    emoji_size = (size * 0.58).round  # taille de police proportionnelle au badge

    # Style : cercle semi-transparent + bordure verte + glow si déverrouillé
    if is_unlocked
      bg     = "rgba(255,255,255,0.07)"
      border = "2px solid #1EDD88"
      shadow = "0 0 0 3px rgba(30,221,136,0.15), 0 0 14px rgba(30,221,136,0.4)"
      opacity = "1"
      filter  = "none"
    else
      bg      = "rgba(255,255,255,0.03)"
      border  = "1px solid rgba(255,255,255,0.06)"
      shadow  = "none"
      opacity = "0.28"
      filter  = "grayscale(1)"
    end

    content_tag(:div,
      data: {
        # Tooltip Bootstrap au survol
        bs_toggle:    "tooltip",
        bs_placement: "top",
        bs_title:     achievement.name,
        # Stimulus : ouvre la modal et passe les données du badge
        action:                              "click->achievement-modal#open",
        achievement_modal_emoji_param:       emoji,
        achievement_modal_name_param:        achievement.name,
        achievement_modal_description_param: achievement.description,
        achievement_modal_xp_param:          achievement.xp_reward,
        achievement_modal_unlocked_param:    is_unlocked.to_s
      },
      style: [
        "width:#{size}px; height:#{size}px;",
        "border-radius:9999px;",
        "display:flex; align-items:center; justify-content:center;",
        "background:#{bg};",
        "border:#{border};",
        "box-shadow:#{shadow};",
        "opacity:#{opacity};",
        "filter:#{filter};",
        "cursor:default; flex-shrink:0;",
        "transition: box-shadow 0.2s, opacity 0.2s, filter 0.2s;"
      ].join(" ")
    ) do
      # Emoji natif centré, taille proportionnelle au badge
      content_tag(:span, emoji,
        style: "font-size:#{emoji_size}px; line-height:1; display:block; text-align:center;"
      )
    end
  end
  # ── Avatar utilisateur ────────────────────────────────────────────────────
  # Affiche l'avatar d'un utilisateur :
  #   - Si un avatar est attaché → image normale
  #   - Sinon → div avec les initiales (Prénom + Nom) sur fond coloré
  #
  # La couleur est déterministe : elle dépend de l'id de l'utilisateur,
  # donc elle ne change pas entre les rechargements de page.
  #
  # Paramètres :
  #   user       – objet User (doit avoir un profil avec first_name/last_name)
  #   css_class  – classes CSS à appliquer (ex: "avatar", "match-avatar")
  #   style      – styles CSS inline supplémentaires
  #   alt        – texte alternatif (par défaut : nom d'affichage)
  def user_avatar_tag(user, css_class: nil, style: nil, alt: nil)
    # Palette de couleurs vives pour les avatars à initiales
    colors = %w[#E63946 #2A9D8F #E76F51 #457B9D #6A4C93 #F4A261 #264653 #2B9348 #C77DFF #FF6B6B]

    # Couleur choisie de façon déterministe selon l'id de l'utilisateur
    color = colors[(user.id.to_i) % colors.length]

    profil    = user.try(:profil)
    alt_text  = alt || user.try(:display_name) || user.email

    if profil&.avatar&.attached?
      # ── Cas 1 : avatar uploadé ───────────────────────────────────────────
      # On utilise rails_blob_path (chemin relatif) plutôt que profil.avatar directement.
      # Dans les contextes Turbo Stream broadcast, url_for peut générer une URL absolue
      # avec un mauvais host (ex: example.com). rails_blob_path évite ce problème
      # car il génère un chemin relatif qui fonctionne partout.
      image_tag rails_blob_path(profil.avatar.blob), class: css_class, alt: alt_text, style: style
    else
      # ── Cas 2 : initiales sur fond coloré ───────────────────────────────
      first    = profil&.first_name&.first&.upcase
      last     = profil&.last_name&.first&.upcase
      initials = [first, last].compact.join
      initials = user.email&.first&.upcase || "?" if initials.blank?

      content_tag :div, initials,
        class: css_class,
        alt:   alt_text,
        style: [
          "background-color:#{color};",
          "color:#fff;",
          "display:flex;align-items:center;justify-content:center;",
          "font-weight:400;font-size:0.7em;",
          style
        ].compact.join(" ")
    end
  end

  # ── Icônes de sport ───────────────────────────────────────────────────────
  # Affiche l'icône d'un sport : image si c'est un fichier, emoji sinon
  # Utilisé partout où on affiche l'icône d'un sport
  def sport_icon(sport, size: "1.1em", css_class: nil)
    return "" unless sport
    if sport.icon.match?(/\.(png|jpg|svg|gif|webp)$/i)
      image_tag sport.icon,
                alt: sport.name,
                class: css_class,
                style: "width:#{size}; height:#{size}; object-fit:contain; vertical-align:middle;"
    else
      content_tag :span, sport.icon, class: css_class
    end
  end

  # Texte brut pour les attributs data-* et les options de select (pas de HTML)
  def sport_icon_text(sport)
    return "" unless sport
    sport.icon.match?(/\.(png|jpg|svg|gif|webp)$/i) ? "" : sport.icon
  end

  # HTML échappé pour stocker dans data-label-html (utilisé par JS pour innerHTML).
  # Retourne une string NON html_safe → ERB l'échappe automatiquement en &lt;img...&gt;
  # Le navigateur la décode dans dataset.labelHtml avant de la passer à innerHTML.
  def sport_icon_html_attr(sport, size: "1rem")
    return "" unless sport
    if sport.icon.match?(/\.(png|jpg|svg|gif|webp)$/i)
      # On construit le tag manuellement pour retourner une string ordinaire (non safe)
      src = asset_path(sport.icon)
      "<img src=\"#{src}\" alt=\"#{sport.name}\" style=\"width:#{size};height:#{size};object-fit:contain;vertical-align:middle;\"> #{sport.name}"
    else
      "#{sport.icon} #{sport.name}"
    end
  end
end
