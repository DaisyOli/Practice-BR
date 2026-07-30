require 'rails_helper'

RSpec.describe "Invitations", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin)   { create(:user, :admin) }
  let(:teacher) { create(:user, :teacher) }
  let(:student) { create(:user, :student) }

  describe "GET /users/invitation/new" do
    context "como professora" do
      it "retorna 200" do
        sign_in teacher
        get new_user_invitation_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "como admin" do
      it "retorna 200" do
        sign_in admin
        get new_user_invitation_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "como aluno" do
      it "redireciona" do
        sign_in student
        get new_user_invitation_path
        expect(response).to redirect_to(root_path)
      end
    end

    context "sem login" do
      it "redireciona para login" do
        get new_user_invitation_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    it "marca o nível como obrigatório e traz o aviso de validação" do
      sign_in teacher
      get new_user_invitation_path

      expect(response.body).to include("Obrigatório. Define quais atividades")
      expect(response.body).to include('id="level-error"')
      expect(response.body).to include('id="invite-form"')
    end
  end

  describe "POST /users/invitation — nível obrigatório" do
    it "recusa convite de aluno sem nível" do
      sign_in teacher

      expect {
        post user_invitation_path, params: { user: { email: "sem-nivel@email.com" } }
      }.not_to change(User, :count)

      # O JS barra antes de enviar, mas o model é a garantia de verdade — vale
      # para convite feito por API, console ou JS desligado.
      expect(response.body).to include("Level")
    end

    it "aceita convite de aluno com nível" do
      sign_in teacher

      expect {
        post user_invitation_path, params: { user: { email: "com-nivel@email.com", level: "B1" } }
      }.to change(User, :count).by(1)

      expect(User.find_by(email: "com-nivel@email.com").level).to eq("B1")
    end
  end

  describe "POST /users/invitation — força role trial para professoras" do
    let(:invite_email) { "aluno-novo@email.com" }

    context "professora tentando convidar" do
      it "cria convite com role trial, mesmo se tentar enviar teacher" do
        sign_in teacher
        expect {
          post user_invitation_path, params: {
            user: { email: invite_email, role: "teacher", level: "A1" }
          }
        }.to change(User, :count).by(1)

        invited = User.find_by(email: invite_email)
        expect(invited.role).to eq("trial")
      end
    end

    context "admin convidando professor" do
      it "permite criar convite com role teacher" do
        sign_in admin
        expect {
          post user_invitation_path, params: {
            user: { email: invite_email, role: "teacher" }
          }
        }.to change(User, :count).by(1)

        invited = User.find_by(email: invite_email)
        expect(invited.role).to eq("teacher")
      end
    end
  end
end
