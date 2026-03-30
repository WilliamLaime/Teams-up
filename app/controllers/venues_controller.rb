class VenuesController < ApplicationController
  # Ce controller ne gère que la recherche d'établissements sportifs (pas de CRUD)
  # Il est appelé en AJAX par le Stimulus controller "place-search"

  # Ignore Pundit pour ce controller (pas de policy nécessaire sur une recherche publique)
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  # POST /venues/find_or_create
  # Appelée quand l'user sélectionne un résultat Nominatim (OSM) non présent en BDD.
  # Cherche une venue existante par name+city (insensible à la casse).
  # Si absente → la crée avec les données OSM passées en JSON.
  # Retourne { id, name, city } pour que le JS puisse stocker le vrai ID.
  def find_or_create
    name = params[:name].to_s.strip
    city = params[:city].to_s.strip

    # Sécurité minimale : name et city sont obligatoires
    if name.blank? || city.blank?
      render json: { error: "Nom et ville requis" }, status: :unprocessable_entity
      return
    end

    # Cherche d'abord une venue existante (insensible à la casse via ILIKE)
    # puis crée si absent. Le rescue gère les rares cas de race condition.
    venue = Venue.where("LOWER(name) = ? AND LOWER(city) = ?", name.downcase, city.downcase).first

    if venue.nil?
      # Crée la venue avec les données Nominatim
      venue = Venue.create(
        name:           name,
        city:           city,
        address:        params[:address].to_s.strip.presence,
        postal_code:    params[:postal_code].to_s.strip.presence,
        sport_type:     params[:sport_type].to_s.strip.presence,
        latitude:       params[:latitude].to_f.nonzero?,
        longitude:      params[:longitude].to_f.nonzero?,
        from_nominatim: true   # Marque cette venue comme ajoutée via OSM
      )
    end

    if venue.persisted?
      render json: { id: venue.id, name: venue.name, city: venue.city }
    else
      render json: { error: venue.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  # GET /venues/search?q=...&lat=...&lon=...
  # Retourne un tableau JSON d'établissements sportifs correspondants
  #
  # Paramètres :
  #   q   → texte recherché (nom, ville, adresse, type de sport)
  #   lat → latitude GPS de l'utilisateur (optionnel)
  #   lon → longitude GPS de l'utilisateur (optionnel)
  def search
    query = params[:q].to_s.strip
    lat   = params[:lat].to_f  # 0.0 si absent
    lon   = params[:lon].to_f  # 0.0 si absent

    venues = Venue.all

    # ── Filtre texte ─────────────────────────────────────────────────────────
    # Cherche dans le nom, la ville, l'adresse et le type de sport
    # ILIKE = insensible à la casse (PostgreSQL)
    if query.length >= 2
      venues = venues.where(
        "name ILIKE :q OR city ILIKE :q OR address ILIKE :q OR sport_type ILIKE :q",
        q: "%#{query}%"
      )
    end

    # ── Filtre et tri par proximité ───────────────────────────────────────────
    if lat.nonzero? && lon.nonzero?
      # Formule de distance euclidienne au carré (pas besoin de PostGIS pour trier)
      distance_sql = Arel.sql("(latitude - #{lat})^2 + (longitude - #{lon})^2 ASC")

      # Étape 1 : chercher dans un rayon de ~30km (0.27° ≈ 30km, car 1° ≈ 111km)
      delta = 0.27
      candidates = venues
                   .where(latitude: (lat - delta)..(lat + delta),
                          longitude: (lon - delta)..(lon + delta))
                   .order(distance_sql)
                   .limit(60)
                   .to_a
                   .uniq { |v| [v.name.to_s.downcase, v.city.to_s.downcase] }

      # Étape 2 : aucun résultat dans les 30km → élargit à toute la France
      # Exemple : l'user cherche "Le Five" depuis une ville qui n'en a pas → on cherche plus loin
      if candidates.empty?
        candidates = venues
                     .order(distance_sql)
                     .limit(60)
                     .to_a
                     .uniq { |v| [v.name.to_s.downcase, v.city.to_s.downcase] }
      end

      venues = candidates.first(8)
    else
      # Pas de GPS → tri par pertinence : noms plus courts d'abord (plus proches de la requête),
      # puis alphabétique. Ex: "LE FIVE BORDEAUX" (16 chars) avant "LE FIVE / COMPLEXE..." (30 chars)
      venues = venues.order(Arel.sql("LENGTH(name), name")).limit(60).to_a
                     .uniq { |v| [v.name.to_s.downcase, v.city.to_s.downcase] }
                     .first(8)
    end

    # Retourne le JSON avec uniquement les champs utiles pour le frontend
    render json: venues.map { |v|
      {
        id: v.id,
        name: v.name,
        sport_type: v.sport_type,
        address: v.address,
        city: v.city,
        postal_code: v.postal_code,
        longitude: v.longitude,
        latitude: v.latitude
      }
    }
  end
end
