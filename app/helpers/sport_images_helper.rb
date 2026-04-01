# Helper centralisé pour les images de sports hébergées sur Cloudinary.
# Toutes les vues doivent utiliser ce helper au lieu des chemins assets locaux.
#
# Usage dans une vue :
#   images = sport_images_for("football")       # → tableau d'URLs Cloudinary
#   url    = sport_cover_image(match)           # → URL déterministe ou aléatoire
#   url    = SPORT_MISC_IMAGES[:multisports]    # → image multisports

module SportImagesHelper

  # Hash principal : slug du sport → liste d'URLs Cloudinary
  SPORT_IMAGES = {
    "football" => %w[
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061590/sports/football/Duel.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061592/sports/football/Medellin.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061594/sports/football/ballon.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061595/sports/football/bresil.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061597/sports/football/city1.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061599/sports/football/citydrone.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061600/sports/football/citytoulouse.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061602/sports/football/herbe.webp
    ],
    "tennis" => %w[
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061604/sports/tennis/tennis1.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061606/sports/tennis/tennis2.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061608/sports/tennis/tennis3.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061611/sports/tennis/tennis4.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061612/sports/tennis/tennis5.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061615/sports/tennis/tennis6.webp
    ],
    "padel" => %w[
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061618/sports/padel/padel1.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061619/sports/padel/padel2.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061621/sports/padel/padel3.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061623/sports/padel/padel4.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061625/sports/padel/padel5.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061627/sports/padel/padel6.webp
    ],
    "volleyball" => %w[
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061629/sports/volleyball/volley1.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061631/sports/volleyball/volley2.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061633/sports/volleyball/volley3.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061635/sports/volleyball/volley4.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061637/sports/volleyball/volley5.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061639/sports/volleyball/volley6.webp
    ],
    "basketball" => %w[
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061641/sports/basketball/basket1.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061643/sports/basketball/basket2.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061645/sports/basketball/basket3.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061646/sports/basketball/basket4.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061648/sports/basketball/basket5.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061649/sports/basketball/basket6.webp
    ],
    "handball" => %w[
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061651/sports/handball/handball1.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061653/sports/handball/handball2.webp
    ],
    "badminton" => %w[
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061654/sports/badminton/badminton1.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061656/sports/badminton/badminton2.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061658/sports/badminton/badminton3.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061660/sports/badminton/badminton4.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061662/sports/badminton/badminton5.webp
      https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061663/sports/badminton/badminton6.webp
    ]
  }.freeze

  # Images diverses (icônes, illustrations génériques)
  SPORT_MISC_IMAGES = {
    multisports:     "https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061664/sports/misc/multisports.png",
    multisports_img: "https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061666/sports/misc/multisports-img.png",
    padel_icon:      "https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061667/sports/misc/padel.png"
  }.freeze

  # Retourne la liste d'URLs pour un sport donné (slug).
  # Si le sport est inconnu, retourne les images football par défaut.
  def sport_images_for(sport_slug)
    SPORT_IMAGES[sport_slug.to_s] || SPORT_IMAGES["football"]
  end

  # Retourne l'URL de couverture pour un match :
  # - utilise match.banner_image si définie manuellement
  # - sinon rotation déterministe : le même match aura toujours la même image
  def sport_cover_image(match)
    return match.banner_image if match.banner_image.present?

    images = sport_images_for(match.sport&.slug || "football")
    images[match.id % images.length]
  end

end
