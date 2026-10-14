require 'rails_helper'

# O link dos emails do teste faz login. Os testes cobrem os dois lados: a pessoa
# certa entra e cai onde o email prometeu; e o link não vira atalho de login
# para mais ninguém.
RSpec.describe "Entrada pelos emails do teste", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include Devise::Test::IntegrationHelpers

  let!(:atividade) { create(:activity, :B1, draft: false) }
  let(:pessoa)     { create(:user, :trial, level: "B1") }

  def link_para(user, to: "activity", activity: atividade)
    trial_link_path(token: TrialEmailLink.generate(user, to: to, activity: activity))
  end

  it "entra sem senha e cai direto na atividade" do
    get link_para(pessoa)

    expect(response).to redirect_to(solve_activity_path(atividade))
    follow_redirect!
    expect(response).to have_http_status(:ok)
  end

  it "registra o primeiro acesso" do
    get link_para(pessoa)
    follow_redirect!

    expect(pessoa.reload.first_access_at).to be_present
  end

  it "funciona mais de uma vez — antivírus de email clica antes da pessoa" do
    link = link_para(pessoa)
    get link
    sign_out pessoa
    get link

    expect(response).to redirect_to(solve_activity_path(atividade))
  end

  it "vale de outro aparelho, sem a sessão da landing" do
    # É o caso que motivou o link: cadastro no computador, email no celular.
    get link_para(pessoa, to: "dashboard")

    expect(response).to redirect_to(student_dashboard_path)
  end

  it "leva à dashboard se a atividade saiu do ar" do
    link = link_para(pessoa)
    atividade.update!(draft: true)

    get link
    expect(response).to redirect_to(student_dashboard_path)
  end

  it "leva à dashboard se a atividade é de outro nível (o teste não abre)" do
    outra = create(:activity, :A2, draft: false)

    get link_para(pessoa, activity: outra)
    expect(response).to redirect_to(student_dashboard_path)
  end

  it "com teste vencido, entra e mostra a tela de fim — não uma porta quebrada" do
    pessoa.update_column(:trial_expires_at, 1.hour.ago)

    get link_para(pessoa)
    follow_redirect!
    expect(response).to redirect_to(trial_expired_path)
  end

  describe "o que o link não pode fazer" do
    it "vence em 8 dias" do
      link = link_para(pessoa)

      travel 9.days do
        get link
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    it "para de valer quando a pessoa escolhe uma senha" do
      link = link_para(pessoa)
      pessoa.update_column(:password_set_at, Time.current)

      get link
      expect(response).to redirect_to(new_user_session_path)
    end

    it "não loga professora" do
      professora = create(:user, :teacher)
      token = TrialEmailLink.generate(professora, to: "dashboard")

      get trial_link_path(token: token)
      expect(response).to redirect_to(new_user_session_path)
    end

    it "não loga aluno pagante" do
      aluno = create(:user, role: "student", level: "B1", password_set_at: nil)
      token = TrialEmailLink.generate(aluno, to: "dashboard")

      get trial_link_path(token: token)
      expect(response).to redirect_to(new_user_session_path)
    end

    it "recusa token adulterado" do
      get trial_link_path(token: TrialEmailLink.generate(pessoa) + "x")
      expect(response).to redirect_to(new_user_session_path)
    end

    it "recusa o token da landing (outro propósito)" do
      get trial_link_path(token: TrialStartToken.generate(pessoa))
      expect(response).to redirect_to(new_user_session_path)
    end

    it "não aceita destino inventado" do
      expect { TrialEmailLink.generate(pessoa, to: "https://evil.example") }
        .to raise_error(ArgumentError)
    end
  end
end
