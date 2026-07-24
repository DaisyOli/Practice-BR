require 'rails_helper'

RSpec.describe "GET /activities — catálogo por nível", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:teacher) { create(:user, :teacher) }

  context "professora logada" do
    before { sign_in teacher }

    it "mostra os títulos publicados agrupados por nível" do
      create(:activity, :A1, title: "Apresentações no trabalho", draft: false)
      create(:activity, :B1, title: "Viagem ao Nordeste", draft: false)

      get activities_path

      expect(response.body).to include("Catálogo por nível")
      expect(response.body).to include("Apresentações no trabalho")
      expect(response.body).to include("Viagem ao Nordeste")
    end

    it "não revela rascunhos de outra professora no catálogo" do
      create(:activity, :A2, title: "Rascunho Secreto de Outra Professora", draft: true, teacher: create(:user, :teacher))

      get activities_path

      expect(response.body).not_to include("Rascunho Secreto de Outra Professora")
    end

    it "avisa quando um nível ainda não tem nada publicado" do
      get activities_path
      expect(response.body).to include("Nada publicado ainda neste nível")
    end
  end

  context "aluno logado" do
    before { sign_in create(:user, :student) }

    it "não mostra o catálogo (é uma ferramenta de professor)" do
      get activities_path
      expect(response.body).not_to include("Catálogo por nível")
    end
  end
end
