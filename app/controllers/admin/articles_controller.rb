# Controller admin pour gérer les articles de blog.
# Accessible uniquement aux admins (Admin::BaseController).
# CRUD complet + actions publier/dépublier.
module Admin
  class ArticlesController < Admin::BaseController

    # Charge l'article avant les actions qui en ont besoin
    before_action :set_article, only: [:show, :edit, :update, :destroy, :publish, :unpublish]

    # GET /admin/articles
    # Liste tous les articles (publiés ET brouillons), du plus récent au plus ancien.
    def index
      @articles = Article.order(created_at: :desc)
    end

    # GET /admin/articles/new
    # Formulaire de création d'un nouvel article.
    def new
      @article = Article.new
    end

    # POST /admin/articles
    # Crée un nouvel article (brouillon par défaut).
    def create
      @article = Article.new(article_params)

      if @article.save
        redirect_to admin_articles_path, notice: "Article \"#{@article.title}\" créé."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # GET /admin/articles/:id/edit
    # Formulaire de modification d'un article existant.
    def edit
    end

    # PATCH /admin/articles/:id
    # Met à jour un article existant.
    def update
      if @article.update(article_params)
        redirect_to admin_articles_path, notice: "Article \"#{@article.title}\" mis à jour."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /admin/articles/:id
    # Supprime un article définitivement.
    def destroy
      @article.destroy
      redirect_to admin_articles_path, notice: "Article supprimé."
    end

    # PATCH /admin/articles/:id/publish
    # Publie l'article (définit published_at à maintenant).
    def publish
      @article.publish!
      redirect_to admin_articles_path, notice: "\"#{@article.title}\" publié."
    end

    # PATCH /admin/articles/:id/unpublish
    # Dépublie l'article (repasse en brouillon).
    def unpublish
      @article.unpublish!
      redirect_to admin_articles_path, notice: "\"#{@article.title}\" repassé en brouillon."
    end

    private

    # Charge l'article par son id — lève une exception 404 si introuvable
    def set_article
      @article = Article.find(params[:id])
    end

    # Paramètres autorisés pour la création/modification d'un article
    def article_params
      params.require(:article).permit(
        :title,
        :slug,
        :body,
        :meta_description,
        :category,
        :cover_image_url,
        :reading_time_minutes
      )
    end
  end
end
