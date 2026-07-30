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
    end

    trait :admin do
      role  { 'teacher' }
      admin { true }
    end
  end
end
