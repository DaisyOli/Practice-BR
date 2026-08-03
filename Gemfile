source "https://rubygems.org"

ruby "3.3.5"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 7.1.5"
gem 'devise'
gem 'devise_invitable'
gem 'simple_form'
gem 'sassc-rails', '~> 2.1'
gem 'tailwindcss-rails', '~> 3.3.1'
gem 'rails-i18n', '~> 7.0.0'
gem 'http_accept_language'

gem 'jquery-rails'

# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem "sprockets-rails"

# Use postgresql as the database for Active Record
gem "pg"

# CORS para o endpoint público de trial (aceita requisições da landing page)
gem "rack-cors"
# Rate limiting do endpoint público de trial
gem "rack-attack"
gem "stripe", "~> 13.0"
gem "web-push"

# Relatório de erros. Sem isto, um 500 na cara de um aluno só é descoberto se ele
# escrever contando — e a maioria não escreve, desiste. Ver config/initializers/sentry.rb:
# fica inteiramente desligado enquanto SENTRY_DSN não existir.
gem "sentry-ruby", "~> 5.21"
gem "sentry-rails", "~> 5.21"

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"

# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"


# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"

# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Redis adapter to run Action Cable in production
# gem "redis", ">= 4.0.1"

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

# Cloudinary para armazenamento de mídia em produção
gem "cloudinary"
gem "ruby-openai", "~> 7.0"

# Adiciona ostruct para compatibilidade futura
gem 'ostruct'

# Gems para assets
gem 'sass-rails'
gem 'terser'  # JavaScript compressor

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ]
  gem "dotenv-rails"
  
  # Gems de teste (SEGURO - só para desenvolvimento e teste)
  gem 'rspec-rails', '~> 6.0'
  gem 'factory_bot_rails'
  gem 'shoulda-matchers'
  gem 'faker'
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
  gem "letter_opener"
  gem 'letter_opener_web'
  gem 'bullet'

  # Add speed badges [https://github.com/MiniProfiler/rack-mini-profiler]
  # gem "rack-mini-profiler"

  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
  
  # Gems adicionais para testes (SEGURO - só para testes)
  gem 'simplecov', require: false
  gem 'database_cleaner-active_record'
end

# Gems para o Heroku
group :production do
  # Dependência recomendada pelo Heroku
  gem 'rails_12factor'
  
  # Gems para cache
  gem 'dalli' # Cliente para Memcached
  gem 'connection_pool' # Pooling de conexões
  gem 'kgio'  # Gem para aumentar a performance do Dalli
  gem 'rack-cache' # Cache HTTP para requisições
end

gem "kaminari", "~> 1.2"

# IA
gem "anthropic"

# Fila de background jobs no Postgres (correção por IA fora do ciclo da requisição)
gem "good_job", "~> 4.0"
