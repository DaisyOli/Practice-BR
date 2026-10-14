require 'rails_helper'

# A admin atribui alunos às professoras. Quem vem do teste nasce aluno da
# Daisy; daqui ela distribui. A professora atribuída passa a ver todo o
# trabalho do aluno — como a Daisy vê —, e as duas pontas recebem email.
RSpec.describe "Atribuir alunos às professoras", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:daisy)     { create(:user, :admin, name: "Daisy") }
  let(:cheyenne)  { create(:user, :teacher, name: "Cheyenne") }
  let(:aluna)     { create(:user, :student, name: "Marina", level: "B1", invited_by_id: daisy.id, language: "pt") }
  # A atividade é da Daisy: é o caso real — o percurso manda todo aluno por elas.
  let!(:da_daisy) { create(:activity, :B1, draft: false, teacher: daisy) }

  before { create(:quiz_attempt, user: aluna, activity: da_daisy, score: 80) }

  describe "a admin" do
    before { sign_in daisy }

    it "vê todos os alunos, com o seletor de professora" do
      create(:user, :student, name: "Da Cheyenne", invited_by_id: cheyenne.id)
      get teacher_students_path

      expect(response.body).to include("Todos os alunos")
      expect(response.body).to include("Marina")
      expect(response.body).to include("Da Cheyenne")
      expect(response.body).to include(teacher_student_assign_path(aluna))
    end

    it "filtra quem ficou sem professora" do
      create(:user, :student, name: "Órfã", invited_by_id: nil)
      get teacher_students_path(professora: "sem")

      expect(response.body).to include("Órfã")
      expect(response.body).not_to include("Marina")
    end

    it "atribui e avisa a professora e o aluno" do
      perform_enqueued_jobs do
        patch teacher_student_assign_path(aluna), params: { teacher_id: cheyenne.id }
      end

      expect(aluna.reload.invited_by_id).to eq(cheyenne.id)
      para = ActionMailer::Base.deliveries.map { |m| [m.to.first, m.subject] }.to_h
      expect(para[cheyenne.email]).to include("Nova pessoa na sua turma: Marina · B1")
      expect(para[aluna.email]).to include("Cheyenne agora acompanha você")
    end

    it "não manda email quando nada muda" do
      expect { patch teacher_student_assign_path(aluna), params: { teacher_id: daisy.id } }
        .not_to have_enqueued_mail
    end

    it "pode deixar sem professora, sem avisar ninguém" do
      expect { patch teacher_student_assign_path(aluna), params: { teacher_id: "" } }
        .not_to have_enqueued_mail
      expect(aluna.reload.invited_by_id).to be_nil
    end
  end

  it "professora comum não atribui" do
    sign_in cheyenne
    patch teacher_student_assign_path(aluna), params: { teacher_id: cheyenne.id }

    expect(aluna.reload.invited_by_id).to eq(daisy.id)
  end

  describe "a professora atribuída vê todo o trabalho do aluno" do
    before do
      aluna.update!(invited_by_id: cheyenne.id)
      sign_in cheyenne
    end

    it "na lista, mesmo que ele só tenha feito atividades da Daisy" do
      get teacher_students_path

      expect(response.body).to include("Marina")
      expect(response.body).to include("Meus Alunos")
    end

    it "no perfil e nas atividades" do
      get teacher_student_profile_path(aluna)
      expect(response).to have_http_status(:ok)

      get teacher_student_activities_path(aluna)
      expect(JSON.parse(response.body)["html"]).to be_present
    end

    it "não vê aluno de outra professora" do
      outro = create(:user, :student, invited_by_id: daisy.id)
      get teacher_student_profile_path(outro)

      expect(response).to redirect_to(teacher_students_path)
    end
  end

  it "o email do aluno sai mesmo para quem descadastrou dos lembretes — é sobre a conta" do
    aluna.update_column(:marketing_emails_opted_out_at, 1.day.ago)

    expect { StudentMailer.teacher_assigned(aluna, cheyenne).deliver_now }
      .to change { ActionMailer::Base.deliveries.size }.by(1)
  end

  it "o email do aluno fala o idioma dele" do
    aluna.update_column(:language, "fr")
    mail = StudentMailer.teacher_assigned(aluna.reload, cheyenne)

    expect(mail.subject).to eq("Cheyenne vous accompagne sur Practice-BR 🌱")
  end
end
