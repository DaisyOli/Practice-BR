# Smoke tests de renderização: garantem que as páginas principais respondem
# 200 e o ERB compila — rede de proteção para refatorações de views/CSS.
require 'rails_helper'

RSpec.describe "Renderização das páginas principais", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:teacher)   { create(:user, :teacher) }
  let(:student)   { create(:user, :student) }
  let!(:activity) { create(:activity, teacher: teacher) }
  let!(:question) { create(:question, :multiple_choice, activity: activity) }

  it "show da activity (professora, com formulários de conteúdo)" do
    sign_in teacher
    get activity_path(activity)
    expect(response).to have_http_status(:ok)
  end

  it "formulário de nova questão" do
    sign_in teacher
    get new_activity_question_path(activity)
    expect(response).to have_http_status(:ok)
  end

  it "dashboard do aluno" do
    sign_in student
    get student_dashboard_path
    expect(response).to have_http_status(:ok)
  end

  it "índice de atividades (aluna)" do
    sign_in student
    get activities_path
    expect(response).to have_http_status(:ok)
  end

  it "tela de resolver o quiz" do
    sign_in student
    get solve_activity_path(activity)
    expect(response).to have_http_status(:ok)
  end

  # A política é pública e é o que um auditor abre primeiro: precisa renderizar
  # deslogada, nas três versões. Cada uma segue um regime jurídico diferente, daí
  # conferir uma marca do texto e não só o 200.
  %w[fr en pt].each do |lang|
    it "política de privacidade (#{lang}), sem estar logada" do
      get privacy_path(lang: lang)
      expect(response).to have_http_status(:ok)
    end
  end

  it "a política declara os prazos de conservação nas três versões" do
    { "fr" => "3 ans", "en" => "3 years", "pt" => "3 anos" }.each do |lang, prazo|
      get privacy_path(lang: lang)
      expect(response.body).to include(prazo), "versão #{lang} não declara o prazo de retenção"
    end
  end
end
