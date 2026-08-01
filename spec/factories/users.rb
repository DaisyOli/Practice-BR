FactoryBot.define do
  factory :user do
    email { Faker::Internet.email }
    password { 'password123' }
    password_confirmation { 'password123' }
    role { 'student' }
    language { 'pt' }
    # Todo aluno tem nível — a validação do User cobre student e trial. A factory
    # precisa refletir isso pra produzir registros válidos por padrão.
    level { 'B1' }
    # Conta comum é de quem escolheu a própria senha. Quem vem da landing não é,
    # e o trait :trial desfaz isso — é a diferença que decide o formulário de
    # senha depois do pagamento e a validade do link do email.
    password_set_at { Time.current }

    trait :teacher do
      role { 'teacher' }
      level { nil } # professora não tem nível CEFR
    end

    trait :student do
      role { 'student' }
    end

    trait :english do
      language { 'en' }
    end

    trait :french do
      language { 'fr' }
    end

    trait :trial do
      role                  { 'trial' }
      level                 { 'B1' }
      trial_expires_at      { 7.days.from_now }
      trial_activities_used { 0 }
      # A conta nasce com senha aleatória na API da landing: ninguém escolheu nada.
      password_set_at       { nil }
    end

    trait :admin do
      role  { 'teacher' }
      admin { true }
    end
  end
end
