require 'rails_helper'

# "~N min · M exercícios" em todo lugar onde a pessoa escolhe uma atividade,
# antes de começar (ponto 2.2, 18/11/2026). A conta está em
# spec/models/activity_size_spec.rb; aqui é onde ela aparece.
RSpec.describe "Tempo e tamanho nos cartões", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:aluno) { create(:user, :student, level: "B1") }
  let!(:pilula) do
    create(:activity, :B1, draft: false, pill: true, statement: nil, explanation_text: nil, title: "Na padaria")
  end

  before do
    4.times { create(:question, :multiple_choice, activity: pilula) }
    create(:question, :open_ended, activity: pilula) # o desafio: fora da conta
  end

  def trecho(corpo, marca, tamanho = 4000)
    inicio = corpo.index(marca) or raise "não achei #{marca}"
    corpo[inicio, tamanho]
  end

  it "\"Continue estudando\" mostra o tempo, os exercícios e o desafio opcional" do
    create(:quiz_attempt, user: aluno, activity: create(:activity, :B1, draft: false)) # já praticou
    sign_in aluno

    get student_dashboard_path

    cartao = trecho(response.body, 'id="tour-continue"')
    expect(cartao).to include("Na padaria", "~3 min", "4 exercícios", "desafio opcional")
  end

  it "o cartão da lista do nível usa a mesma conta" do
    sign_in aluno

    get student_dashboard_path(level: "B1")

    cartao = trecho(response.body, "Na padaria", 3000)
    expect(cartao).to include("~3 min", "4 exercícios", "desafio opcional")
    expect(response.body).not_to include("questões")
  end

  it "\"Comece por aqui\" diz quanto tempo leva" do
    sign_in create(:user, :trial, level: "B1")

    get student_dashboard_path

    expect(trecho(response.body, "Comece por aqui")).to include("Nível B1 · ~3 min · 4 exercícios")
  end

  it "a página do quiz mostra o tempo, para quem chega direto pelo email" do
    sign_in aluno

    get solve_activity_path(pilula)

    expect(trecho(response.body, "quiz-page-header", 2000)).to include("~3 min")
  end

  it "o \"Próxima atividade\" do resultado diz quanto tempo a próxima leva" do
    feita = create(:activity, :B1, draft: false, title: "No mercado")
    questao = create(:question, :multiple_choice, activity: feita)
    sign_in aluno
    post submit_activity_path(feita), params: { answers: { questao.id.to_s => "Brasília" } }

    get results_activity_path(feita)

    expect(trecho(response.body, "Na padaria", 600)).to include("~3 min · 4 exercícios")
  end
end
