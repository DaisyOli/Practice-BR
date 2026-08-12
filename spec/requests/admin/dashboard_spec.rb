require 'rails_helper'

RSpec.describe "Admin::Dashboard", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin)   { create(:user, :admin) }
  let(:teacher) { create(:user, :teacher) }
  let(:student) { create(:user, :student) }

  describe "GET /admin" do
    context "como admin" do
      it "retorna 200" do
        sign_in admin
        get admin_root_path
        expect(response).to have_http_status(:ok)
      end

      # O bloco de ferramentas foi reorganizado em 11/08/2026 em dois grupos.
      # Até então o spec só olhava o código de status, então um card podia
      # desaparecer num refactor de layout sem nenhum teste reclamar — que é
      # exatamente o tipo de perda que ninguém nota até precisar da ferramenta.
      describe "o bloco de ferramentas" do
        before do
          sign_in admin
          get admin_root_path
        end

        it "separa o que cria do que só informa" do
          expect(response.body).to include("Criar conteúdo")
          expect(response.body).to include("Entender e ajustar")
        end

        it "mostra as cinco ferramentas" do
          %w[Agente\ de\ Conteúdo Do\ Vídeo Sugestões\ do\ Dia
             Atividades\ por\ Avaliação A\ voz\ das\ IAs].each do |ferramenta|
            expect(response.body).to include(ferramenta),
              "sumiu do painel: #{ferramenta}"
          end
        end

        it "leva a cor certa para cada papel" do
          # Escuro = caminho principal; branco com borda = não produz conteúdo.
          expect(response.body).to include("admin-tool--hero")
          expect(response.body).to include("admin-tool--quiet")
        end
      end

      it "esconde o crachá de rascunhos quando não há nenhum" do
        sign_in admin
        get admin_root_path

        expect(response.body).not_to include("0 rascunhos")
      end

      it "mostra o crachá quando há rascunho esperando" do
        create(:activity, teacher: teacher, ai_generated: true, draft: true)

        sign_in admin
        get admin_root_path

        expect(response.body).to include("1 rascunho<")
      end
    end

    context "como professora sem admin" do
      it "redireciona com alerta de acesso restrito" do
        sign_in teacher
        get admin_root_path
        expect(response).to redirect_to(root_path)
      end
    end

    context "como aluno" do
      it "redireciona" do
        sign_in student
        get admin_root_path
        expect(response).to redirect_to(root_path)
      end
    end

    context "sem login" do
      it "redireciona para login" do
        get admin_root_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
