require 'rails_helper'

# A lista de atividades lembra o último filtro (pedido da Daisy, 18/11/2026,
# no meio da faxina do A1): filtrar por nível e "Mais longas", abrir uma
# atividade, cortar e voltar pelo "← Atividades" zerava a lista.
RSpec.describe "Lista de atividades: os filtros ficam guardados", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:professora) { create(:user, :teacher) }

  before { sign_in professora }

  it "voltar para a lista sem filtro devolve o último filtro usado" do
    get activities_path(level: "A1", sort: "duracao", view: "grid")
    expect(response).to have_http_status(:ok)

    get activities_path # o "← Atividades", o menu, o redirecionamento depois de arquivar

    expect(response).to redirect_to(activities_path(level: "A1", sort: "duracao", view: "grid"))
  end

  it "o voltar da página da atividade leva à lista filtrada" do
    atividade = create(:activity, :A1, teacher: professora, draft: false)
    get activities_path(level: "A1", sort: "duracao")

    get activity_path(atividade)
    expect(response.body).to include(%(href="#{activities_path}"))
    get activities_path

    expect(response).to redirect_to(activities_path(level: "A1", sort: "duracao"))
  end

  it "\"✕ Limpar\" esquece de verdade" do
    get activities_path(level: "A1", sort: "duracao")
    expect(response.body).to include(activities_path(limpar: 1))

    get activities_path(limpar: 1)
    expect(response).to redirect_to(activities_path)

    get activities_path
    expect(response).to have_http_status(:ok)
  end

  it "um filtro novo substitui o antigo" do
    get activities_path(level: "A1", sort: "duracao")
    get activities_path(level: "B2")

    get activities_path
    expect(response).to redirect_to(activities_path(level: "B2"))
  end

  it "a busca leva junto a visualização, a origem e a competência" do
    get activities_path(view: "grid", origem: "ia", competencia: "ce", level: "A1")

    %w[view origem competencia].each do |filtro|
      expect(response.body).to match(/<input[^>]*type="hidden"[^>]*name="#{filtro}"[^>]*>/)
    end
    expect(response.body).to include('name="view" value="grid"', 'name="origem" value="ia"')
  end

  it "dá para sair das arquivadas mesmo com elas lembradas" do
    get activities_path(arquivadas: "1")
    expect(response.body).to include(activities_path(arquivadas: "0"))

    get activities_path(arquivadas: "0")
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("📦 Arquivada\n")
  end

  it "sair da conta esquece o filtro (a próxima pessoa começa do zero)" do
    get activities_path(level: "A1")
    get destroy_user_session_path # o "Sair" de verdade (GET neste app), que limpa a sessão
    sign_in create(:user, :teacher)

    get activities_path
    expect(response).to have_http_status(:ok)
  end
end
