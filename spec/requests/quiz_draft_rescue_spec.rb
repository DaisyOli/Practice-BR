# Em 04/08/2026 o banco ficou intermitente por horas e o único aluno pagante
# perdeu a redação que tinha acabado de escrever: o envio falhou e a página de
# erro levou junto tudo que estava no formulário.
#
# O conserto é o quiz-rescue, que guarda as respostas no navegador. Estes testes
# cobrem o que o Ruby consegue ver — que a fiação chega no HTML. A lógica de
# guardar e devolver vive no controller Stimulus.
require 'rails_helper'

RSpec.describe "Resgate do rascunho do quiz", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:teacher)   { create(:user, :teacher) }
  let(:student)   { create(:user, :student) }
  let!(:activity) { create(:activity, teacher: teacher) }
  let!(:question) { create(:question, :multiple_choice, activity: activity) }

  before { sign_in student }

  describe "tela de resolver" do
    before { get solve_activity_path(activity) }

    it "liga o quiz-rescue no formulário" do
      expect(response.body).to include("quiz-rescue")
    end

    it "usa uma chave por aluno e por atividade, para não misturar rascunhos" do
      expect(response.body).to include("#{student.id}:#{activity.slug}")
    end

    it "deixa o aviso de recuperação pronto, escondido até fazer falta" do
      expect(response.body).to include('data-quiz-rescue-target="notice"')
    end
  end

  describe "tela de resultados" do
    it "manda apagar o rascunho, porque o envio já foi salvo" do
      create(:quiz_attempt, user: student, activity: activity)
      get results_activity_path(activity)

      expect(response.body).to include('data-quiz-rescue-mode-value="clear"')
      expect(response.body).to include("#{student.id}:#{activity.slug}")
    end
  end
end
