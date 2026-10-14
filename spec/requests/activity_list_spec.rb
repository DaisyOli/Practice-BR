require 'rails_helper'

# A lista que a professora manda aos alunos: o percurso na ordem, depois o resto
# por tema, com o link de cada atividade.
RSpec.describe "Lista de atividades para os alunos", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:teacher) { create(:user, :teacher) }
  let!(:primeira) { create(:activity, :A1, draft: false, title: "Olá! Como você está?", theme: "Cumprimentos") }
  let!(:segunda)  { create(:activity, :A1, draft: false, title: "Emoções", theme: "Sentimentos") }
  let!(:comida)   { create(:activity, :A1, draft: false, title: "Na feira", theme: "Comida") }
  let!(:sem_tema) { create(:activity, :A1, draft: false, title: "Atividade solta") }
  let!(:rascunho) { create(:activity, :A1, draft: true, title: "Rascunho secreto") }

  before do
    Activity.set_path!("A1", [segunda.id, primeira.id])
    sign_in teacher
  end

  it "mostra o percurso na ordem, depois o resto por tema, com os links" do
    get activity_list_path(level: "A1")
    corpo = CGI.unescapeHTML(response.body)

    expect(corpo).to include("Comece por estas, nesta ordem")
    expect(corpo.index("Emoções")).to be < corpo.index("Olá! Como você está?")
    expect(corpo).to include("Mais atividades, por tema")
    expect(corpo.index("Comida")).to be < corpo.index("Outros temas")
    expect(corpo).to include(solve_activity_path(comida))
    expect(corpo).not_to include("Rascunho secreto")
  end

  it "o texto para copiar segue a mesma ordem" do
    get activity_list_path(level: "A1")
    texto = Nokogiri::HTML(response.body).at_css("#copy-text").text

    expect(texto).to start_with("📚 Practice-BR · Atividades A1")
    expect(texto).to include("1. Emoções (Sentimentos) — http")
    expect(texto).to include("▸ Comida\n• Na feira — http")
  end

  it "sem percurso, lista tudo por tema" do
    get activity_list_path(level: "B1")
    expect(response.body).to include("Ainda não há atividades publicadas no B1")
  end

  it "é só para professoras" do
    sign_in create(:user, :student)
    get activity_list_path
    expect(response).to redirect_to(root_path)
  end

  it "tem o link na dashboard da professora" do
    get teacher_dashboard_path
    expect(response.body).to include(activity_list_path)
  end
end
