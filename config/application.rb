require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module TeamUp
  class Application < Rails::Application
    config.generators do |generate|
      generate.assets false
      generate.helper false
      generate.test_framework :test_unit, fixture: false
    end
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # Fuseau horaire de l'application : France (Paris)
    # Time.current retournera l'heure française au lieu de l'heure UTC
    config.time_zone = "Paris"
    # config.eager_load_paths << Rails.root.join("extras")

    # Langue par défaut de l'application : français
    # Utilisé par time_ago_in_words, les messages d'erreur, etc.
    config.i18n.default_locale = :fr

    # Pages d'erreur personnalisées avec notre vrai layout (navbar + styles)
    # Au lieu des pages statiques public/404.html, Rails utilisera notre ErrorsController
    config.exceptions_app = routes
  end
end
