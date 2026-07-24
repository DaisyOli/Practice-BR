Rails.application.routes.draw do
  # Rota inicial
  root to: 'home#index'

  # Rotas para dashboards
  get   'student_dashboard',                        to: 'students#dashboard'
  patch 'student_dashboard/weekly_reminder_toggle', to: 'students#toggle_weekly_reminder', as: :student_toggle_weekly_reminder
  get   'students/load_more',                       to: 'students#load_more'
  get 'students/open_ended_attempts', to: 'students#open_ended_attempts', as: 'student_open_ended_attempts'
  get 'teacher_dashboard', to: 'teachers#dashboard'
  get 'teachers/ratings/more', to: 'teachers#more_ratings', as: 'teacher_more_ratings'
  get    'teachers/students',                        to: 'teachers#students',              as: 'teacher_students'
  get    'teachers/students/:id/activities',          to: 'teachers#student_activities',    as: 'teacher_student_activities'
  get    'teachers/students/:id/written',             to: 'teachers#student_written',       as: 'teacher_student_written'
  get    'teachers/students/:id/attestation',         to: 'teachers#student_attestation',   as: 'teacher_student_attestation'
  get    'teachers/students/:id',                    to: 'teachers#student_profile',       as: 'teacher_student_profile'
  patch  'teachers/students/:id/level',              to: 'teachers#update_student_level',  as: 'teacher_student_level'
  delete 'teachers/students/:id',                    to: 'teachers#remove_student',        as: 'teacher_student_remove'
  patch  'teachers/students/:id/clear_comments',     to: 'teachers#clear_student_comments', as: 'teacher_student_clear_comments'
  patch  'quiz_attempts/:id/teacher_comment',        to: 'teacher_comments#update',        as: 'quiz_attempt_teacher_comment'
  
  # PWA manifest
  get '/manifest.json', to: 'pwa#manifest', as: :pwa_manifest

  # Rota para atualização de idioma
  patch 'update_language', to: 'languages#update'
  
  # Rotas do Devise para autenticação
  devise_for :users, controllers: {
    invitations: 'invitations'
  }

  # Rotas para atividades e questões
  resources :activities, param: :slug do
    collection do
      get  :generate_with_ai
      post :generate_with_ai
      get  :generate_from_video
      post :generate_from_video
      get "generations/:id",        action: :generation_wait,   as: :generation_wait
      get "generations/:id/status", action: :generation_status, as: :generation_status
    end

    member do
      get  :review_draft
      post :publish_draft
      get  :solve,      action: :resolve_quiz
      get  :grading_status
      post :submit,     action: :submit_quiz
      get  :submit,     to: redirect { |params, _req| "/activities/#{params[:slug]}/solve" }
      get  :results,    action: :quiz_results
      post :transcribe, action: :transcribe_audio
      match "clear/:content", action: :clear_content, via: [:patch, :post], as: :clear_content,
            constraints: { content: /statement|media|video|explanation|audio|image_file|video_file/ }
      delete :clear_attempt_history
    end

    resources :activity_ratings, only: [:create, :update], path: 'ratings'
    resources :questions
    resources :suggestions, only: [:create, :destroy]
    resources :sentence_orderings, only: [:create, :update, :destroy]
    resources :paragraph_orderings, only: [:create, :update, :destroy] do
      resources :paragraph_sentences, only: [:create, :destroy]
    end
    resources :column_matchings, only: [:create, :update, :destroy] do
      resources :matching_pairs, only: [:create, :destroy]
    end
  end

  # Dashboard administrativa
  namespace :admin do
    root to: "dashboard#index"
    resources :drafts, only: [:index, :destroy]
    post "drafts/generate", to: "drafts#generate", as: :generate_draft
    post "trials/:id/send_reminder", to: "trials#send_reminder", as: :send_trial_reminder
    resources :activities, only: [:index]

    resources :activity_suggestions, only: [:index] do
      member do
        post :approve
        post :reject
      end
      collection do
        post :generate_now
      end
    end
  end

  # API pública para trial
  namespace :api do
    namespace :v1 do
      resources :trials, only: [:create]
    end
  end

  # Assinatura Stripe
  get  "assinar",              to: "billing#new",              as: :billing_new
  post "assinar/checkout",     to: "billing#create_checkout",  as: :billing_checkout
  get  "assinar/sucesso",      to: "billing#success",          as: :billing_success
  get  "assinar/cancelado",    to: "billing#cancel",           as: :billing_cancel
  post "assinar/cancelar",     to: "billing#cancel_subscription", as: :billing_cancel_subscription
  post "webhooks/stripe",      to: "webhooks#stripe"
  resources :push_subscriptions, only: [:create, :destroy]

  # Página de acesso trial encerrado
  get "acesso-encerrado", to: "home#trial_expired", as: "trial_expired"

  # Health check para monitoramento
  get "up" => "rails/health#show", as: :rails_health_check

  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end
end
