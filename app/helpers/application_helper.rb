module ApplicationHelper
  # Pagy::Frontend fournit les helpers de vue pour afficher la navigation de pagination
  # ex: pagy_bootstrap_nav(@pagy) dans les vues admin
  include Pagy::Frontend

  # ── Fil d'Ariane ──────────────────────────────────────────────────────────────
  # Rend le fil d'Ariane d'une page ET son JSON-LD BreadcrumbList, d'un seul appel.
  #
  # @param crumbs [Array] maillons du fil, du plus général au plus précis, sous la
  #   forme `[libellé, chemin]`. Le DERNIER maillon est la page courante : son
  #   chemin est ignoré (on ne se lie pas à soi-même). L'accueil est ajouté
  #   automatiquement en tête — il est le même sur tout le site, le répéter dans
  #   chaque vue n'était qu'une occasion de l'écrire différemment.
  #
  # Les deux sorties viennent de la MÊME source : le fil affiché et le fil déclaré
  # à Google ne peuvent plus diverger, ce qui était le risque quand chaque page les
  # écrivait à la main (cf. l'ancien fil en dur de l'article de blog).
  #
  # Usage type, dans une vue :
  #   <% content_for :breadcrumb, breadcrumb_for([["Tournois", tournaments_path],
  #                                               [@tournament.name, nil]]) %>
  #
  # `bare: true` sur les pages à bannière pleine largeur : le fil est alors rendu
  # directement dans la vue, à l'intérieur du .container de la bannière, plutôt
  # que via `content_for` — le poser au-dessus décollerait la bannière de la navbar.
  # `on_dark: true` en complément quand cette bannière est sombre (cf. le partial).
  def breadcrumb_for(crumbs, bare: false, on_dark: false)
    crumbs = [["Accueil", root_path]] + Array(crumbs)
    render "shared/breadcrumb", crumbs: crumbs, bare: bare, on_dark: on_dark
  end

  # Le JSON-LD correspondant, appelé par le partial. `position` commence à 1
  # (schema.org), et le dernier maillon n'a pas d'`item` : c'est la page courante.
  #
  # URI.join plutôt que `url_for(only_path: false)` : les vues passent des chemins
  # déjà construits (`tournaments_path` → "/tournois"), et `url_for` rend une
  # chaîne telle quelle, donc relative — or schema.org exige des URLs absolues et
  # ignore silencieusement le reste.
  def breadcrumb_json_ld(crumbs)
    items = crumbs.each_with_index.map do |(label, path), index|
      item = { "@type" => "ListItem", "position" => index + 1, "name" => label.to_s }
      item["item"] = URI.join(root_url, path.to_s).to_s if path.present? && index < crumbs.size - 1
      item
    end

    { "@context" => "https://schema.org", "@type" => "BreadcrumbList",
      "itemListElement" => items }.to_json
  end

  # Génère un badge achievement avec le style exactement issu du Figma Teams-up :
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
  #   loading    – "lazy" ou "eager", défaut "lazy" (RGESN 6.4)
  #   width      – largeur HTML en px, défaut 40
  #   height     – hauteur HTML en px, défaut 40
  def user_avatar_tag(user, css_class: nil, style: nil, alt: nil, loading: "lazy", width: 40, height: 40)
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
      # RGESN 6.4 (lazy loading) + RGESN 5.2 (dimensions) — évite les reflows (CLS)
      image_tag rails_blob_path(profil.avatar.blob),
                class: css_class,
                alt: alt_text,
                style: style,
                loading: loading,
                width: width,
                height: height
    else
      # ── Cas 2 : initiales sur fond coloré ───────────────────────────────
      first    = profil&.first_name&.first&.upcase
      last     = profil&.last_name&.first&.upcase
      initials = [first, last].compact.join
      initials = user.email&.first&.upcase || "?" if initials.blank?

      # Fallback avatar div avec initialer — ajouter role="img" pour l'accessibilité
      content_tag :div, initials,
                  class: css_class,
                  role: "img",
                  aria_label: alt_text,
                  style: [
                    "background-color:#{color};",
                    "color:#fff;",
                    "display:flex;align-items:center;justify-content:center;",
                    "font-weight:400;font-size:0.7em;",
                    "width:#{width}px;height:#{height}px;",
                    style
                  ].compact.join(" ")
    end
  end

  # ── Avatar cliquable → profil public de l'utilisateur ───────────────────────
  # Identique à user_avatar_tag, mais enveloppe l'avatar dans un lien vers le
  # profil public. À utiliser UNIQUEMENT là où l'avatar n'est pas déjà à
  # l'intérieur d'un autre lien (les liens HTML imbriqués sont invalides).
  # data-turbo-frame="_top" force la navigation pleine page même si l'avatar est
  # rendu à l'intérieur d'un turbo-frame (ex: fenêtre de chat).
  def user_avatar_link(user, **options)
    return user_avatar_tag(user, **options) if user.blank?

    link_to user_profil_path(user),
            class: "user-avatar-link",
            title: user.try(:display_name).presence || user.email,
            data: { turbo_frame: "_top" } do
      user_avatar_tag(user, **options)
    end
  end

  # ── Icônes de sport ───────────────────────────────────────────────────────
  # Affiche l'icône d'un sport : image si c'est un fichier, emoji sinon
  # Utilisé partout où on affiche l'icône d'un sport
  # RGESN 5.2 Frontend — ajouter width/height HTML attrs pour éviter le CLS
  def sport_icon(sport, size: "1.1em", css_class: nil, px_size: 18)
    return "" unless sport

    if sport.icon.match?(/\.(png|jpg|svg|gif|webp)$/i)
      # RGESN 5.2 — ajoute f_auto,q_auto aux URLs Cloudinary (PNG → WebP auto selon navigateur)
      icon_url = cloudinary_optimized_url(sport.icon)
      image_tag icon_url,
                alt: sport.name,
                class: css_class,
                width: px_size,
                height: px_size,
                style: "width:#{size}; height:#{size}; object-fit:contain; vertical-align:middle;"
    else
      content_tag :span, sport.icon, class: css_class
    end
  end

  # ── Badge de niveau ──────────────────────────────────────────────────────────
  # Retourne la classe CSS à appliquer sur un badge de niveau.
  # Le niveau est traduit en "tier" (1 à 7) selon sa position dans la grille du sport.
  # Tier 1 = débutant (vert) → Tier 7 = expert (violet), "Tout niveau" = bleu neutre.
  #
  # Paramètres :
  #   level_label – chaîne du niveau (ex: "Confirmé")
  #   sport       – objet Sport (optionnel) pour un mapping précis selon la grille du sport
  def level_badge_css(level_label, sport = nil)
    return "level-tout" if level_label.blank? || level_label == "Tout niveau"

    if sport.present?
      levels = sport.available_levels.map { |l| l[:label] }
      index  = levels.index(level_label)

      if index
        # Normalise la position (0..n-1) en tier (1..7)
        # Guard contre division par zéro si un seul niveau dans la grille
        tier = ((index.to_f / [levels.length - 1, 1].max) * 6).round + 1
        "level-tier-#{tier.clamp(1, 7)}"
      else
        "level-tout" # niveau inconnu / héritage → badge neutre
      end
    else
      # Pas de contexte sport → fallback sur le nom du label
      case level_label
      when "Débutant" then "level-tier-1"
      when "Amateur", "Initié", "Perfectionnement", "Élémentaire" then "level-tier-2"
      when "Intermédiaire"     then "level-tier-3"
      when "Confirmé"          then "level-tier-5"
      when "Avancé"            then "level-tier-6"
      when "Expert"            then "level-tier-7"
      else "level-tout"
      end
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
      src = cloudinary_optimized_url(sport.icon)
      img_style = "width:#{size};height:#{size};object-fit:contain;vertical-align:middle;"
      "<img src=\"#{src}\" alt=\"#{sport.name}\" style=\"#{img_style}\"> #{sport.name}"
    else
      "#{sport.icon} #{sport.name}"
    end
  end

  # Libellé de date relatif et lisible pour un match (ex. carte "match à la une").
  #   - Aujourd'hui       → "Ce soir" si le match est à 18h ou plus, sinon "Aujourd'hui"
  #   - Demain            → "Demain"
  #   - Dans la semaine   → jour en toutes lettres (ex. "Mardi")
  #   - Au-delà           → date courte (ex. "14 juil.")
  def match_day_label(match)
    return "" unless match&.date

    date  = match.date
    today = Date.current

    if date == today
      match.time && match.time.hour >= 18 ? "Ce soir" : "Aujourd'hui"
    elsif date == today + 1
      "Demain"
    elsif date <= today + 6
      # Jour de la semaine en français, première lettre en majuscule
      I18n.l(date, format: "%A").capitalize
    else
      # Date courte : jour + mois abrégé (ex. "14 juil.")
      I18n.l(date, format: "%-d %b")
    end
  end

  private

  # RGESN 5.2 — injecte les transformations Cloudinary f_auto,q_auto dans une URL Cloudinary.
  # f_auto : sert WebP ou AVIF selon le navigateur (30-50% plus léger que PNG/JPEG).
  # q_auto : compression automatique sans perte de qualité perceptible.
  # Les URLs non-Cloudinary sont retournées inchangées.
  def cloudinary_optimized_url(url)
    return url unless url.to_s.include?("res.cloudinary.com")
    return url if url.include?("f_auto") # déjà optimisée

    url.sub(%r{/image/upload/}, "/image/upload/f_auto,q_auto/")
  end
end
