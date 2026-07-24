FactoryBot.define do
  factory :activity_suggestion do
    association :teacher, factory: [:user, :teacher]
    theme { "Pedir comida por app de delivery" }
    level_hint { "A1" }
    rationale { "Nenhum tema recente sobre delivery no catálogo." }
    status { "pending" }
  end
end
