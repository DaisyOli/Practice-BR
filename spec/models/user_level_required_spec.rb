require 'rails_helper'

# "Todo aluno tem nível" era uma regra que existia só na cabeça da Daisy: os
# níveis entraram no produto depois do resto, e o código nunca soube dela. A
# validação valia só para trial, e essa inconsistência criava uma armadilha na
# transição de papel (ver spec/requests/stripe_webhooks_spec.rb).
RSpec.describe User, "nível obrigatório para aluno", type: :model do
  it "exige nível de quem é student" do
    aluno = build(:user, :student, level: nil)

    expect(aluno).not_to be_valid
    expect(aluno.errors[:level]).to be_present
  end

  it "exige nível de quem é trial" do
    trial = build(:user, :trial, level: nil)

    expect(trial).not_to be_valid
    expect(trial.errors[:level]).to be_present
  end

  it "NÃO exige nível de professora" do
    professora = build(:user, :teacher, level: nil)

    expect(professora).to be_valid
  end

  it "recusa nível fora da escala CEFR" do
    aluno = build(:user, :student, level: "Z9")

    expect(aluno).not_to be_valid
  end

  it "mantém o registro válido quando o papel muda de student para trial" do
    # Este é o cenário que quebrava: o registro era válido como student e ficava
    # inválido como trial, justamente na hora em que o webhook do Stripe rebaixa
    # o aluno por cancelamento de assinatura.
    aluno = create(:user, :student, level: "B2")

    aluno.role = "trial"

    expect(aluno).to be_valid
  end
end
