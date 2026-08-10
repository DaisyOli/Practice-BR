require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

require_relative "../app/middleware/database_connection_retry"

module PracticePt
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w(assets tasks))

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    
    # Configuração de internacionalização
    config.i18n.load_path += Dir[Rails.root.join('config', 'locales', '**', '*.{rb,yml}')]
    config.i18n.available_locales = [:en, :pt, :'pt-BR', :fr]
    config.i18n.default_locale = :pt
    config.i18n.fallbacks = true
    
    # Configuração de fuso horário
    # Paris, e não Brasília: o conteúdo é brasileiro, mas as pessoas não são.
    # Toda a base é francófona e mora na França, e era o fuso delas que decidia
    # coisas do dia a dia — quando a ofensiva vira de dia, quando o limite
    # diário de exercícios reseta, quantos dias de prática o professor vê. Com
    # Brasília o dia virava às 4h ou 5h da manhã em Paris.
    #
    # Os crons já diziam Europe/Paris; agora o app concorda com eles. O banco
    # guarda tudo em UTC, então isto muda interpretação e exibição, não dado.
    #
    # Quando a base passar de um fuso só, isto vira coluna por usuário — hoje
    # seria complexidade sem ninguém para servir.
    config.time_zone = 'Paris'

    # Adicionar autoload para services
    config.autoload_paths += %W(#{config.root}/app/services)
    config.eager_load_paths += %W(#{config.root}/app/services)

    config.middleware.use DatabaseConnectionRetry
  end
end
