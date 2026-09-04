require "test_helper"

# ── Carte Slack d'un match ────────────────────────────────────────────────────
# Deux mises en page cohabitent et il est facile de casser l'une en touchant
# l'autre : un match OUVERT recrute (niveau, places, liste d'inscrits), une
# rencontre de TOURNOI rend compte (adversaires fixés par le tirage, puis score).
# Ces tests fixent ce qui distingue les deux, et le passage « affiche » → « résultat ».
class Slack::BlockKitBuilderTest < ActiveSupport::TestCase
  setup do
    @builder = Slack::BlockKitBuilder.new
    @sport   = Sport.create!(name: "Ping test", slug: "ping-#{SecureRandom.hex(4)}", icon: "🏓")
    @user    = create_test_user(email: "orga-bk@example.com", first_name: "Zoé", last_name: "Organise")

    @tournament = Tournament.create!(name: "Open démo", sport: @sport, user: @user,
                                     format: "ronde_suisse", status: "in_progress",
                                     max_players: 8, date: Date.tomorrow, place: "Salle test")
    @round = @tournament.tournament_rounds.create!(phase: "swiss", number: 1, status: "in_progress")
    @lea   = tournament_player("Léa", "Martin")
    @tom   = tournament_player("Tom", "Roux")
    @tmatch = @round.tournament_matches.create!(player_a: @lea, player_b: @tom, position: 0)
  end

  teardown { teardown_db }

  def tournament_player(first, last)
    user = create_test_user(email: "#{first.parameterize}-#{SecureRandom.hex(3)}@example.com",
                            first_name: first, last_name: last)
    @tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
  end

  # La rencontre réelle rattachée à la carte du tableau (celle que les joueurs
  # créent pour convenir de leur créneau, et qui est partagée dans Slack).
  def confrontation
    Match.create!(title: "Ping-Pong — Léa Martin vs Tom Roux",
                  date: Date.tomorrow, time: Time.current.change(hour: 18, min: 15),
                  players_needed: 2, level: "Débutant", visibility: "public",
                  validation_mode: "automatic", genre_restriction: "tous",
                  user: @user, sport: @sport,
                  tournament: @tournament, tournament_match: @tmatch)
  end

  def open_match
    Match.create!(title: "Foot du jeudi", date: Date.tomorrow,
                  time: Time.current.change(hour: 19, min: 0),
                  players_needed: 10, level: "Débutant", visibility: "public",
                  validation_mode: "automatic", genre_restriction: "tous",
                  user: @user, sport: @sport)
  end

  # Les champs Block Kit du bloc de détails, dans l'ordre où Slack les affiche
  # (gauche → droite, deux par ligne).
  def detail_texts(blocks)
    blocks.find { |b| b[:type] == "section" && b[:fields] }[:fields].map { |f| f[:text] }
  end

  # ── Mise en page d'une confrontation ────────────────────────────────────────
  # La demande est littérale : les adversaires à DROITE de « Quand ». Slack
  # remplissant les champs deux par ligne, cela veut dire « en position 2 ».
  test "confrontation : les adversaires sont le champ juste après Quand" do
    texts = detail_texts(@builder.match_created_blocks(confrontation))

    assert_match(/\A\*Quand\*/, texts[0])
    assert_match(/\A\*Adversaires\*/, texts[1])
    assert_match(/Léa M\..*Tom R\./, texts[1])
  end

  # Gain de place : ni « Sport » (l'emoji de tête et le titre le disent déjà),
  # ni « Niveau », ni « Joueurs 2/2 » sur une rencontre à deux joueurs désignés.
  test "confrontation : pas de champ Sport, Niveau ni Joueurs" do
    texts = detail_texts(@builder.match_created_blocks(confrontation))

    assert_no_match(/\*Sport\*/, texts.join)
    assert_no_match(/\*Niveau\*/, texts.join)
    assert_no_match(/\*Joueurs\*/, texts.join)
  end

  # Les adversaires vivant dans les champs, la section « inscrits » ferait doublon.
  test "confrontation : aucune section d'inscrits en plus des champs" do
    blocks = @builder.match_created_blocks(confrontation)
    sections = blocks.select { |b| b[:type] == "section" }

    assert_equal 1, sections.size, "un seul bloc section : celui des champs"
  end

  # La carte est ré-éditée sur place : « Nouveau match » deviendrait faux dès
  # que le score tombe.
  test "confrontation : le titre ne dit pas « Nouveau match »" do
    header = @builder.match_created_blocks(confrontation).first

    assert_equal "🏓 Ping-Pong — Léa Martin vs Tom Roux", header[:text][:text]
  end

  # ── Passage au résultat ─────────────────────────────────────────────────────
  test "score saisi : le champ Adversaires devient le champ Score" do
    @tmatch.assign_score([[11, 5], [11, 7]])
    @tmatch.save!

    texts = detail_texts(@builder.match_created_blocks(confrontation.reload))

    assert_match(/\A\*Score\*/, texts[1])
    assert_match(/Léa M\..*\*2\*.*\*0\*.*Tom R\./, texts[1])
  end

  test "score saisi : le tag de statut annonce le vainqueur" do
    @tmatch.assign_score([[11, 5], [11, 7]])
    @tmatch.save!

    context = @builder.match_created_blocks(confrontation.reload).find { |b| b[:type] == "context" }

    assert_equal "🏆 *Terminé* — victoire de Léa M.", context[:elements].first[:text]
  end

  # Le score prime sur l'horloge : la rencontre est à venir, mais elle est jouée.
  test "score saisi : le texte de repli porte le score, pas la date" do
    @tmatch.assign_score([[11, 5], [11, 7]])
    @tmatch.save!

    assert_equal "Ping-Pong — Léa Martin vs Tom Roux — score final 2-0",
                 @builder.match_created_text(confrontation.reload)
  end

  test "sans score : le tag reste le statut horaire" do
    context = @builder.match_created_blocks(confrontation).find { |b| b[:type] == "context" }

    assert_equal "🗓️ *À venir*", context[:elements].first[:text]
  end

  # ── Non-régression : le match ouvert garde sa carte de recrutement ──────────
  test "match ouvert : Sport, Niveau, Joueurs et liste d'inscrits sont conservés" do
    blocks = @builder.match_created_blocks(open_match)
    texts  = detail_texts(blocks).join

    assert_match(/\*Sport\*/, texts)
    assert_match(/\*Niveau\*/, texts)
    assert_match(/\*Joueurs\*/, texts)
    assert_equal 2, blocks.count { |b| b[:type] == "section" }, "champs + liste d'inscrits"
  end
end
