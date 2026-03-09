class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :home ]

  def home
    # Récupère les 3 prochains matchs à venir, triés par date
    @matches = Match.order(date: :asc).limit(3)
  end
end
