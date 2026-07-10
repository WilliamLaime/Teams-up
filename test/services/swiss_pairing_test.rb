require "test_helper"

# Tests de l'ALGORITHME PUR d'appariement (SwissPairing#build_pairs), sans base.
# Un joueur = un simple Struct répondant à #id, #wins, #set_average, #point_average.
# On simule plusieurs rondes en accumulant les paires jouées, et on vérifie les
# invariants critiques : pas de rematch, byes, groupes impairs, effectifs bâtards,
# départage par set/point average (Lot 4).
class SwissPairingTest < ActiveSupport::TestCase
  # set_average / point_average tombent à 0 s'ils ne sont pas fournis (Lot 4).
  Player = Struct.new(:id, :wins, :set_average, :point_average) do
    def set_average   = self[:set_average] || 0
    def point_average = self[:point_average] || 0
  end

  # Fabrique n joueurs (wins = 0 par défaut).
  def players(count, wins: 0)
    (1..count).map { |i| Player.new(i, wins) }
  end

  # Joue une ronde : renvoie les paires + le bye, et met à jour l'historique
  # (played_pairs) + les byes. Les vainqueurs sont les player_a (arbitraire mais
  # déterministe) pour faire évoluer les scores.
  def play_round(pool, played_pairs, byed_ids)
    result = SwissPairing.new.build_pairs(pool, played_pairs: played_pairs, byed_ids: byed_ids)
    result[:pairs].each { |a, b| played_pairs << [a.id, b.id].minmax }
    byed_ids << result[:bye].id if result[:bye]
    result
  end

  test "ronde 1 : effectif pair → que des paires, aucun bye" do
    result = SwissPairing.new.build_pairs(players(16))
    assert_nil result[:bye]
    assert_equal 8, result[:pairs].size
    # Tous les joueurs sont appariés une seule fois.
    ids = result[:pairs].flat_map { |a, b| [a.id, b.id] }
    assert_equal (1..16).to_a, ids.sort
  end

  test "effectif impair → exactement un bye, le reste apparié" do
    result = SwissPairing.new.build_pairs(players(13))
    assert_not_nil result[:bye]
    assert_equal 6, result[:pairs].size
    ids = result[:pairs].flat_map { |a, b| [a.id, b.id] } + [result[:bye].id]
    assert_equal (1..13).to_a, ids.sort
  end

  test "aucun rematch sur plusieurs rondes (16 joueurs)" do
    pool = players(16)
    played = Set.new
    byes = Set.new

    4.times do
      before = played.size
      result = play_round(pool, played, byes)
      added = result[:pairs].size
      # Chaque paire ajoutée est nouvelle → la taille du Set augmente d'autant.
      assert_equal before + added, played.size, "un rematch a été généré"
    end
  end

  test "un même joueur ne reçoit pas deux byes tant que d'autres n'en ont pas eu" do
    pool = players(7)
    played = Set.new
    byes = Set.new

    seen = []
    5.times do
      result = play_round(pool, played, byes)
      seen << result[:bye].id if result[:bye]
    end
    # Aucun bye dupliqué avant que tout le monde n'y soit passé (7 > nb de rondes ici).
    assert_equal seen.uniq, seen
  end

  test "groupes de victoires différents → float d'un groupe impair" do
    # 4 joueurs à 1 victoire, 2 joueurs à 0 → le groupe des 1V est pair, celui des 0V pair.
    # On force un cas impair : 3 à 1V, 3 à 0V.
    pool = players(3, wins: 1) + [Player.new(4, 0), Player.new(5, 0), Player.new(6, 0)]
    result = SwissPairing.new.build_pairs(pool)
    assert_nil result[:bye] # effectif total pair (6)
    assert_equal 3, result[:pairs].size
    ids = result[:pairs].flat_map { |a, b| [a.id, b.id] }
    assert_equal (1..6).to_a, ids.sort
  end

  # Le point noir cité dans docs/TOURNOI.md : « 24 tend à planter ».
  test "effectifs bâtards ne lèvent jamais (7, 13, 23, 24, 31)" do
    [7, 13, 23, 24, 31].each do |n|
      pool = players(n)
      played = Set.new
      byes = Set.new
      assert_nothing_raised do
        6.times { play_round(pool, played, byes) }
      end
    end
  end

  test "fallback : rematch toléré en dernier recours sans crash" do
    # 4 joueurs qui se sont tous déjà affrontés entre eux → impossible sans rematch.
    pool = players(4)
    played = Set.new
    # Toutes les paires possibles déjà jouées.
    pool.combination(2).each { |a, b| played << [a.id, b.id].minmax }

    result = nil
    assert_nothing_raised { result = SwissPairing.new.build_pairs(pool, played_pairs: played) }
    assert_equal 2, result[:pairs].size
    ids = result[:pairs].flat_map { |a, b| [a.id, b.id] }
    assert_equal (1..4).to_a, ids.sort
  end

  test "départage : à égalité de victoires, le tri suit le set average décroissant" do
    # Mêmes victoires, set averages distincts → l'ordre de tri est
    # [-wins, -set_average, -point_average, id] → 1er avec 2e, 3e avec 4e.
    pool = [
      Player.new(1, 1, 10, 0),
      Player.new(2, 1, 5, 0),
      Player.new(3, 1, 1, 0),
      Player.new(4, 1, 0, 0)
    ]
    result = SwissPairing.new.build_pairs(pool)
    got = result[:pairs].map { |a, b| [a.id, b.id].sort }
    assert_equal [[1, 2], [3, 4]], got.sort
  end

  test "tous les joueurs sont couverts exactement une fois à chaque ronde" do
    [8, 9, 15, 16, 32].each do |n|
      result = SwissPairing.new.build_pairs(players(n))
      covered = result[:pairs].flat_map { |a, b| [a.id, b.id] }
      covered << result[:bye].id if result[:bye]
      assert_equal (1..n).to_a, covered.sort, "couverture incorrecte pour #{n}"
    end
  end
end
