# config/sitemap.rb — Génération du sitemap Teams-up
#
# Ce fichier est utilisé par la gem sitemap_generator pour créer public/sitemap.xml.
# Commandes :
#   rake sitemap:refresh         → génère et ping Google/Bing
#   rake sitemap:refresh:no_ping → génère sans ping (dev / CI)
#
# Google utilise ce fichier pour connaître toutes les pages du site et planifier son crawl.
# priority : 0.0 à 1.0 (importance relative de la page)
# changefreq : always, hourly, daily, weekly, monthly, yearly, never

SitemapGenerator::Sitemap.default_host = "https://www.teams-up-sport.fr"

# Compresse le sitemap en .xml.gz (recommandé — réduction ~90% de la taille)
SitemapGenerator::Sitemap.compress = true

SitemapGenerator::Sitemap.create do

  # ── Pages statiques ───────────────────────────────────────────────────────

  # Page d'accueil — priorité maximale, mise à jour fréquente (badge "X matchs dispo")
  add root_path,
      priority:   1.0,
      changefreq: "daily"

  # Page de découverte des matchs — cœur de l'app, très importante pour le SEO
  add matches_path,
      priority:   0.9,
      changefreq: "hourly"

  # Page "Qui sommes-nous" — rarement modifiée
  add about_path,
      priority:   0.7,
      changefreq: "monthly"

  # Espace tournois — liste publique des tournois
  add tournaments_path,
      priority:   0.8,
      changefreq: "daily"

  # Page contact — stable
  add contact_path,
      priority:   0.5,
      changefreq: "yearly"

  # Page partenariat — stable
  add partenariat_path,
      priority:   0.6,
      changefreq: "yearly"

  # ── Articles de blog ─────────────────────────────────────────────────────
  #
  # On n'indexe que les articles publiés (pas les brouillons).
  # lastmod : date de dernière modification → Google sait quand recrawler
  # changefreq "weekly" : les articles peuvent être mis à jour (stats, liens)
  add articles_path,
      priority:   0.8,
      changefreq: "weekly"

  Article.published.find_each do |article|
    add article_path(article.slug),
        priority:    0.7,
        changefreq:  "weekly",
        lastmod:     article.updated_at
  end

  # ── Pages dynamiques : matchs publics ────────────────────────────────────
  #
  # On n'indexe que les matchs PUBLICS et à venir (pas les matchs privés ni terminés).
  # Un match terminé ou privé n'a aucune valeur SEO.
  Match.publicly_visible.upcoming.find_each do |match|
    add match_path(match),
        priority:    0.7,
        changefreq:  "daily",          # Les infos du match (participants, places restantes) changent souvent
        lastmod:     match.updated_at
  end

  # ── Pages dynamiques : profils publics ────────────────────────────────────
  #
  # Les profils sont actuellement en noindex (ProfilsController#show_user_simple).
  # Raisons : données personnelles (RGPD), contenu changeant, pas de valeur SEO externe.
  # À activer si on ajoute un opt-in "Rendre mon profil visible sur Google" dans les paramètres.
  #
  # User.joins(:match_users)
  #     .where(match_users: { status: "approved" })
  #     .distinct
  #     .find_each do |user|
  #   add user_profil_path(user), priority: 0.5, changefreq: "weekly", lastmod: user.updated_at
  # end

end
