module ApplicationHelper
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
