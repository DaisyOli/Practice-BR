require 'rails_helper'

# A original sai de circulação sozinha quando a série adaptada dela fica
# completa, e a parte 1 assume o lugar dela no percurso (pedido da Daisy,
# 18/11/2026: "não é prático eu ter que procurá-la").
RSpec.describe "Arquivar a original da série adaptada", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:professora) { create(:user, :teacher) }
  let!(:original)  { create(:activity, :A1, teacher: professora, draft: false, title: "Saudações e Apresentações") }

  def parte(posicao, draft: true)
    create(:activity, :A1, teacher: professora, draft: draft, pill: true, ai_generated: true,
                           source_activity: original, series_key: "adaptacao-#{original.id}-teste",
                           series_position: posicao, title: "Saudações: parte #{posicao}")
  end

  before { sign_in professora }

  describe "ao publicar as partes" do
    let!(:p1) { parte(1) }
    let!(:p2) { parte(2) }

    it "publicar uma parte com outra ainda em rascunho não mexe na original" do
      post publish_draft_activity_path(p1)

      expect(original.reload).not_to be_archived
    end

    it "publicar a última parte arquiva a original e avisa" do
      post publish_draft_activity_path(p1)
      post publish_draft_activity_path(p2)

      expect(original.reload).to be_archived
      expect(flash[:notice]).to include("A série está completa", "«Saudações e Apresentações» foi arquivada")
    end

    it "a ordem não importa: vale a última que sai do rascunho" do
      post publish_draft_activity_path(p2)
      expect(original.reload).not_to be_archived

      post publish_draft_activity_path(p1)
      expect(original.reload).to be_archived
    end

    it "a original no percurso: a parte 1 entra no lugar dela" do
      Activity.set_path!("A1", [original.id])

      post publish_draft_activity_path(p1)
      post publish_draft_activity_path(p2)

      expect(original.reload.path_position).to be_nil
      expect(p1.reload.path_position).to eq(1)
      expect(flash[:notice]).to include("A Parte 1 de 2 «Saudações: parte 1» entrou no lugar dela no percurso do A1 (posição 1)")
    end

    it "não arquiva a original de outra professora" do
      original.update!(teacher: create(:user, :teacher))

      post publish_draft_activity_path(p1)
      post publish_draft_activity_path(p2)

      expect(original.reload).not_to be_archived
    end

    it "pílula que não veio de adaptação publica como sempre" do
      solta = create(:activity, :A1, teacher: professora, draft: true, pill: true)

      post publish_draft_activity_path(solta)

      expect(flash[:notice]).to eq("Atividade publicada com sucesso!")
    end
  end

  describe "o botão \"📦 Arquivar a original\"" do
    it "também passa a posição do percurso para a parte 1" do
      p1 = parte(1, draft: false)
      Activity.set_path!("A1", [create(:activity, :A1, draft: false).id, original.id])

      post archive_activity_path(original)

      expect(p1.reload.path_position).to eq(2)
      expect(flash[:notice]).to include("entrou no lugar dela no percurso do A1 (posição 2)")
    end

    it "sem pílula publicada, a posição fica vazia, como antes" do
      parte(1) # ainda em rascunho
      Activity.set_path!("A1", [original.id])

      post archive_activity_path(original)

      expect(original.reload.path_position).to be_nil
      expect(Activity.where(level: "A1").in_path).to be_empty
    end

    it "se a parte 1 já está no percurso, ela não muda de lugar" do
      p1 = parte(1, draft: false)
      Activity.set_path!("A1", [p1.id, original.id])

      post archive_activity_path(original)

      expect(p1.reload.path_position).to eq(1)
      expect(flash[:notice]).not_to include("entrou no lugar dela")
    end
  end
end
