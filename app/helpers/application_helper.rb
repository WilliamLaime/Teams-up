module ApplicationHelper
  # Pagy::Frontend fournit les helpers de vue pour afficher la navigation de pagination
  # ex: pagy_bootstrap_nav(@pagy) dans les vues admin
  include Pagy::Frontend
  # Génère un badge achievement avec le style exactement issu du Figma TeamUp :
  # — cercle plein (border-radius 9999px), fond rgba(255,255,255,0.05)
  # — glow blanc quand déverrouillé, grayscale + opacité réduite quand verrouillé
  # — emoji centré à 28px (adapté à la taille du badge dans l'armoire)
  def achievement_badge(achievement, is_unlocked:, size: 48)
    emoji      = achievement.icon_emoji.presence || "🏅"
    emoji_size = (size * 0.58).round # taille de police proportionnelle au badge

    # Style du cercle — on n'applique PAS opacity sur le wrapper car ça affecterait
    # aussi la tooltip enfant. On met opacity + filter uniquement sur l'emoji span.
    if is_unlocked
      bg           = "rgba(255,255,255,0.07)"
      border       = "2px solid #1EDD88"
      shadow       = "0 0 0 3px rgba(30,221,136,0.15), 0 0 14px rgba(30,221,136,0.4)"
      emoji_style  = "" # aucun filtre — emoji plein
    else
      bg           = "rgba(255,255,255,0.03)"
      border       = "1px solid rgba(255,255,255,0.06)"
      shadow       = "none"
      # opacity + grayscale uniquement sur l'emoji, pas sur le wrapper
      emoji_style  = "opacity:0.28; filter:grayscale(1);"
    end

    content_tag(:div,
                data: {
                  # Stimulus : ouvre la modal et passe les données du badge
                  action: "click->achievement-modal#open",
                  achievement_modal_emoji_param: emoji,
                  achievement_modal_name_param: achievement.name,
                  achievement_modal_description_param: achievement.description,
                  achievement_modal_xp_param: achievement.xp_reward,
                  achievement_modal_unlocked_param: is_unlocked.to_s
                },
                style: [
                  "width:#{size}px; height:#{size}px;",
                  "border-radius:9999px;",
                  "display:flex; align-items:center; justify-content:center;",
                  "background:#{bg};",
                  "border:#{border};",
                  "box-shadow:#{shadow};",
                  "cursor:pointer; flex-shrink:0;",
                  "position:relative;", # nécessaire pour positionner la tooltip
                  "transition: box-shadow 0.2s, filter 0.2s;"
                ].join(" ")) do
      # Emoji centré — opacity/grayscale portés ici pour ne pas affecter la tooltip
      transition_style = "transition: opacity 0.2s, filter 0.2s;"
      emoji_span = content_tag(:span, emoji,
                               style: "font-size:#{emoji_size}px; line-height:1; display:block; " \
                                      "text-align:center; #{emoji_style} #{transition_style}")

      # Tooltip au survol : nom, description, XP et statut
      xp_label     = is_unlocked ? "+#{achievement.xp_reward} XP" : "#{achievement.xp_reward} XP"
      status_label = is_unlocked ? "✓ Débloqué" : "✕ Verrouillé"
      status_color = is_unlocked ? "#1EDD88" : "#ff4d4d" # vert si débloqué, rouge si verrouillé

      tooltip = content_tag(:div, class: "achievement-hover-tip") do
        content_tag(:div, emoji, class: "achievement-hover-tip__emoji") +
          content_tag(:div, achievement.name, class: "achievement-hover-tip__name") +
          content_tag(:div, achievement.description, class: "achievement-hover-tip__desc") +
          content_tag(:div, class: "achievement-hover-tip__footer") do
            content_tag(:span, xp_label, class: "achievement-hover-tip__xp") +
              content_tag(:span, status_label, class: "achievement-hover-tip__status",
                                               style: "color:#{status_color};")
          end
      end

      emoji_span + tooltip
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
    color = colors[user.id.to_i % colors.length]

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
                  alt: alt_text,
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
      img_style = "width:#{size};height:#{size};object-fit:contain;vertical-align:middle;"
      "<img src=\"#{src}\" alt=\"#{sport.name}\" style=\"#{img_style}\"> #{sport.name}"
    else
      "#{sport.icon} #{sport.name}"
    end
  end
end
