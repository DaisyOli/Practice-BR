require 'rails_helper'

# O tempo e o tamanho também nas telas da professora (pedido da Daisy,
# 18/11/2026). Ela quer achar as atividades longas para cortar à mão: adaptar
# cada uma com a IA sai caro, e nem toda longa precisa virar série.
RSpec.describe "Tempo e tamanho nas telas da professora", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:professora) { create(:user, :teacher) }
  let!(:longa) do
    create(:activity, :B1, teacher: professora, draft: false, title: "A longa demais",
                           statement: nil, explanation_text: (["palavra"] * 200).join(" "),
                           video_url: "https://youtu.be/abcdefghijk")
  end
  let!(:curta) do
    create(:activity, :B1, teacher: professora, draft: false, title: "A curtinha",
                           statement: nil, explanation_text: nil)
  end

  before do
    7.times { create(:question, :multiple_choice, activity: longa) }
    create(:question, :multiple_choice, activity: curta)
    sign_in professora
  end

  describe "lista de atividades" do
    it "a grade mostra o tempo e os exercícios em cada cartão" do
      get activities_path(view: "grid")

      # rindex: o título aparece antes no catálogo por nível, no topo da página.
      cartao = response.body[response.body.rindex("A curtinha"), 2500]
      expect(cartao).to include("~2 min", "1 exercício")
    end

    it "a lista mostra o tempo embaixo do título" do
      get activities_path(view: "list")

      # 7 × 0,75 + 200 palavras (4) + vídeo inteiro (5) = 14,25 → 15
      expect(response.body).to include("⏱ ~15 min · 7 exercícios")
    end

    it "\"⏱ Mais longas\" põe as mais longas primeiro" do
      get activities_path(sort: "duracao", view: "list")

      expect(response.body).to include('value="duracao" selected')
      linhas = response.body[response.body.index('class="act-list-grid"')..]
      expect(linhas.index("A longa demais")).to be < linhas.index("A curtinha")
    end

    # Antes, o número contava só a página (no máximo 9).
    it "diz quantas atividades encontrou no total, não só as da página" do
      create_list(:activity, 10, :B1, draft: false)

      %w[recentes duracao tentativas].each do |ordem|
        get activities_path(sort: ordem)
        expect(response.body).to include("12 atividades encontradas"), "ordem #{ordem}"
      end
    end
  end

  describe "página da atividade" do
    it "mostra o tempo e o que passa do tamanho de pílula" do
      get activity_path(longa)

      expect(response.body).to include("~15 min", "7 exercícios", "✂️ Acima do tamanho de pílula",
                                       "7 exercícios fechados (pílula: até 5)", "200 palavras de texto (B1: até 130)",
                                       "vídeo inteiro (pílula: um trecho)")
    end

    it "a que já cabe numa pílula não leva o aviso" do
      get activity_path(curta)

      expect(response.body).to include("~2 min")
      expect(response.body).not_to include("Acima do tamanho de pílula")
    end

    it "a pílula não leva o aviso, e mostra o desafio opcional" do
      longa.update!(pill: true)
      create(:question, :open_ended, activity: longa)

      get activity_path(longa)

      expect(response.body).to include("desafio opcional")
      expect(response.body).not_to include("Acima do tamanho de pílula")
    end
  end

  it "o percurso do admin mostra o tempo em cada opção" do
    sign_in create(:user, :admin)

    get admin_path_path

    expect(response.body).to include("A longa demais — 🎬 vídeo · ⏱ ~15 min · 7 ex")
  end
end
