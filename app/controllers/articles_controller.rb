# Controller public du blog — accessible à tous, connectés ou non.
# GET /blog        → liste des articles publiés
# GET /blog/:slug  → article individuel
class ArticlesController < ApplicationController
  # Pagy::Backend fournit la méthode `pagy(collection, ...)` utilisée dans index
  include Pagy::Backend

  # Les pages du blog sont publiques — pas besoin d'être connecté
  skip_before_action :authenticate_user!, raise: false

  # Pundit vérifie que policy_scope est appelé dans index — on l'ignore ici
  # car le blog est entièrement public, pas de filtrage par utilisateur
  after_action :verify_authorized, except: :index
  after_action :verify_policy_scoped, only: :index
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  # GET /blog
  # Affiche tous les articles publiés, du plus récent au plus ancien.
  # Paginés avec Pagy pour ne pas charger tous les articles d'un coup.
  def index
    @pagy, @articles = pagy(
      Article.published.recent,
      limit: 9 # 9 articles par page (grille 3x3)
    )

    # Catégories disponibles pour le filtre (si paramètre passé)
    @selected_category = params[:category]
    if @selected_category.present?
      @pagy, @articles = pagy(
        Article.published.recent.by_category(@selected_category),
        limit: 9
      )
    end
  end

  # GET /blog/:slug
  # Affiche un article individuel. Retourne 404 si brouillon ou introuvable.
  def show
    # On cherche par slug — retourne 404 automatiquement si absent
    @article = Article.published.find_by!(slug: params[:slug])
  end
end
