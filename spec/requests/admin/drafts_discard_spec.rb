require 'rails_helper'

# "Descartar" na lista de rascunhos do agente de conteúdo. O endereço usa o slug
# da atividade (Activity#to_param), e até 2026-10-14 a ação buscava por número:
# respondia 404 e o botão parecia morto.
RSpec.describe "Descartar rascunho", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:user, :admin) }

  before { sign_in admin }

  it "apaga o rascunho pelo endereço com slug" do
    rascunho = create(:activity, :A1, draft: true, ai_generated: true, title: "Oi, Tudo Bem? Primeiras Palavras")

    delete admin_draft_path(rascunho)

    expect(Activity.exists?(rascunho.id)).to be false
    expect(response).to redirect_to(admin_drafts_path)
    expect(flash[:notice]).to include("descartado")
  end

  it "nunca apaga atividade publicada" do
    publicada = create(:activity, :A1, draft: false)

    delete admin_draft_path(publicada)

    expect(Activity.exists?(publicada.id)).to be true
    expect(flash[:alert]).to include("não encontrado")
  end
end
