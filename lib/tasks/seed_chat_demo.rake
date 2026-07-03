# Génère des conversations de démonstration pour tester le chat en local :
# quelques chats de match, un chat d'équipe et des conversations privées, avec
# des messages aléatoires. Idempotent : relançable sans casser les données.
#
# Usage :
#   bin/rails chat:demo                      # cible le 1er user confirmé
#   EMAIL=laimewilliam@gmail.com bin/rails chat:demo   # cible un user précis
#
# Pour repartir de zéro sur les messages/convs de démo : bin/rails chat:demo_clear
namespace :chat do
  BANTER = [
    "Salut la team, chaud pour samedi ?", "On joue à quelle heure déjà ?",
    "Je ramène le ballon 👍", "Quelqu'un a un dossard en trop ?",
    "Grosse forme aujourd'hui 💪", "Désolé les gars je serai 5 min en retard",
    "On était pas loin de gagner !", "Prochaine fois on les explose 😂",
    "Terrain réservé, c'est bon", "Il manque encore 2 joueurs non ?",
    "Qui gère les boissons ?", "GG à tous, super match", "Je peux inviter un pote ?",
    "Ça marche pour moi 🔥", "On se cale où pour se retrouver ?",
    "Parking gratuit juste à côté", "Pensez à vos crampons, ça glisse",
    "Match serré mais mérité 😎", "Je confirme ma présence", "Faut qu'on bosse la défense 😅"
  ].freeze

  desc "Crée des conversations de démo pour tester le chat (EMAIL=... pour cibler un user)"
  task demo: :environment do
    target = ENV["EMAIL"].present? ? User.find_by(email: ENV["EMAIL"]) : nil
    target ||= User.where.not(confirmed_at: nil).first || User.first
    abort "❌ Aucun utilisateur en base." unless target

    others = User.where.not(id: target.id).to_a
    abort "❌ Il faut au moins 2 utilisateurs." if others.empty?

    puts "🎯 Cible : #{target.email} (##{target.id})"

    # ── 1. Chats de match ─────────────────────────────────────────────────────
    match_ids = target.match_users
                      .where("status = 'approved' OR role = 'organisateur'")
                      .limit(3).pluck(:match_id)

    if match_ids.size < 3
      Match.upcoming.where.not(id: match_ids).order("RANDOM()")
           .limit(3 - match_ids.size).each do |m|
        mu = m.match_users.find_or_initialize_by(user: target)
        mu.update!(status: "approved", role: mu.role.presence || "joueur")
        match_ids << m.id
      end
    end

    Match.where(id: match_ids).each do |m|
      partner = m.match_users.where.not(user_id: target.id)
                 .where("status = 'approved' OR role = 'organisateur'").first&.user
      unless partner
        partner = (others - [target]).sample
        pmu = m.match_users.find_or_initialize_by(user: partner)
        pmu.update!(status: "approved", role: pmu.role.presence || "joueur")
      end
      participants = [target, partner].compact
      rand(4..8).times do
        Message.create!(match: m, user: participants.sample, content: BANTER.sample)
      end
      puts "  💬 Match ##{m.id} (#{m.slug}) — chat alimenté"
    end

    # ── 2. Chat d'équipe ──────────────────────────────────────────────────────
    team = target.team_members.first&.team
    team ||= Team.create!(name: "Les Testeurs #{rand(100..999)}", captain: target)
    others.sample([2, others.size].min).each do |u|
      next if team.team_members.exists?(user: u)

      team.team_members.create!(user: u, role: "member")
    end
    team_members = team.reload.team_members.map(&:user)
    rand(5..9).times do
      Message.create!(team: team, user: team_members.sample, content: BANTER.sample)
    end
    puts "  💬 Équipe ##{team.id} (#{team.slug}) — chat alimenté (#{team_members.size} membres)"

    # ── 3. Conversations privées ──────────────────────────────────────────────
    others.sample([3, others.size].min).each do |u|
      conv = PrivateConversation.find_or_create_by!(sender: target, recipient: u)
      thread = [target, u]
      rand(3..6).times do
        Message.create!(private_conversation: conv, user: thread.sample, content: BANTER.sample)
      end
      puts "  ✉️  Conversation privée avec #{u.email} — alimentée"
    end

    puts "✅ Terminé. Connecte-toi en tant que #{target.email} et ouvre l'icône de chat."
  end

  desc "Supprime tous les messages et conversations privées (remise à zéro du chat)"
  task demo_clear: :environment do
    Message.delete_all
    PrivateConversation.delete_all
    puts "🧹 Messages et conversations privées supprimés."
  end
end
