require "test_helper"

# ── Blog public ───────────────────────────────────────────────────────────────
# La page article portait un fil d'Ariane et un JSON-LD BreadcrumbList écrits à la
# main ; ils viennent désormais du composant partagé (ApplicationHelper#breadcrumb_for).
# Ces tests fixent ce qui doit rester vrai après cette migration : le fil s'affiche,
# le JSON-LD est présent une seule fois, et un brouillon reste introuvable.
class ArticlesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @article = Article.create!(title: "Bien débuter au padel", slug: "bien-debuter-padel",
                               body: "Contenu de test.", published_at: 1.day.ago)
  end

  teardown { teardown_db }

  test "GET /blog/:slug affiche le fil d'Ariane" do
    get article_path(@article.slug)

    assert_response :success
    assert_select "nav.breadcrumb-trail" do
      assert_select "a[href=?]", root_path, text: "Accueil"
      assert_select "a[href=?]", articles_path, text: "Blog"
      assert_select ".breadcrumb-trail__current", text: /Bien débuter au padel/
    end
  end

  # Le fil était déclaré deux fois (nav + JSON-LD recopié) : les deux pouvaient
  # diverger. Ils viennent maintenant de la même source, et il n'y en a qu'un.
  test "GET /blog/:slug ne déclare qu'un seul BreadcrumbList" do
    get article_path(@article.slug)

    assert_equal 1, response.body.scan("BreadcrumbList").size
  end

  test "GET /blog/:slug renvoie 404 pour un brouillon" do
    @article.update!(published_at: nil)

    get article_path(@article.slug)

    assert_response :not_found
  end
end
