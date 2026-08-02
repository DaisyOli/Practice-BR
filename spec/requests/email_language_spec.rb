# O seletor de idioma dos emails.
#
# Existe porque em 01/08/2026 quatro pessoas francófonas receberam email em
# inglês: a coluna `language` nascia com default 'en' e ninguém — nem elas nem a
# Daisy pela interface — tinha como corrigir. Foi preciso migração no banco.
#
# O que estes testes protegem é a saída: a pessoa consegue trocar sozinha, e a
# troca chega nos mailers, que são o único lugar que lê esse campo.
require 'rails_helper'

RSpec.describe "Idioma dos emails", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:student) { create(:user, :student, language: "en") }

  describe "PATCH /update_language" do
    it "troca o idioma e confirma na língua NOVA, não na antiga" do
      sign_in student

      patch update_language_path, params: { language: "fr" }

      expect(student.reload.language).to eq("fr")
      expect(flash[:notice]).to eq(LanguagesController::COPY["fr"][:ok])
    end

    it "aceita os três idiomas que a plataforma publica" do
      sign_in student

      User::LANGUAGES.each do |code|
        patch update_language_path, params: { language: code }
        expect(student.reload.language).to eq(code)
      end
    end

    it "ignora idioma que não existe, sem quebrar nem gravar" do
      sign_in student

      patch update_language_path, params: { language: "de" }

      expect(student.reload.language).to eq("en")
      expect(flash[:alert]).to be_present
    end

    it "exige estar logado" do
      patch update_language_path, params: { language: "fr" }

      expect(response).to redirect_to(new_user_session_path)
    end

    # O Referer é forjável, então o redirect não pode seguir pra fora do app.
    it "não redireciona para outro host mesmo com Referer forjado" do
      sign_in student

      patch update_language_path,
            params: { language: "fr" },
            headers: { "HTTP_REFERER" => "https://exemplo-malicioso.com/pegadinha" }

      expect(response).to redirect_to(student_dashboard_path)
    end
  end

  # A ponta que importa: trocar o idioma tem que mudar o email de verdade. Sem
  # isto o botão seria enfeite.
  describe "o que a pessoa escolhe é o que chega na caixa de entrada" do
    let(:teacher)  { create(:user, :teacher) }
    let(:activity) { create(:activity, teacher: teacher) }

    it "manda o alerta de ausência na língua escolhida" do
      student.update!(language: "fr")
      mail = StudentMailer.inactivity_nudge(student, activity)
      expect(mail.subject).to eq(StudentMailer::INACTIVITY["fr"][:subject])

      student.update!(language: "pt")
      mail = StudentMailer.inactivity_nudge(student, activity)
      expect(mail.subject).to eq(StudentMailer::INACTIVITY["pt"][:subject])
    end
  end

  describe "o seletor aparece na dashboard" do
    it "para quem é aluno" do
      sign_in student
      get student_dashboard_path

      expect(response.body).to include(update_language_path)
      expect(response.body).to include("Français")
    end

    # Trial recebe 4 emails da sequência e é quem mais tem chance de ter nascido
    # com o idioma errado — não pode ficar de fora.
    it "para quem está no teste" do
      trial = create(:user, :student, role: "trial", language: "fr",
                                      trial_expires_at: 7.days.from_now,
                                      trial_activities_used: 0)
      sign_in trial
      get student_dashboard_path

      expect(response.body).to include(update_language_path)
    end
  end
end
