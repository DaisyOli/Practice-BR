require 'rails_helper'

RSpec.describe "Organismo de formação da professora", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:teacher) { create(:user, :teacher) }
  let(:siret)   { "85194793700013" }

  let(:dados_completos) do
    {
      org_name: "Mon Organisme de Formation", org_siret: siret,
      org_nda: "11 75 12345 75", org_address: "12 rue de la Formation, 75011 Paris",
      org_signatory: "Marie Dupont, gérante",
      training_title: "Portugais brésilien — formation à distance"
    }
  end

  describe "quem pode entrar" do
    it "manda aluno para a raiz" do
      sign_in create(:user, :student)
      get teacher_organisation_path
      expect(response).to redirect_to(root_path)
    end

    it "manda visitante para o login" do
      get teacher_organisation_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "GET" do
    before { sign_in teacher }

    it "abre e diz que preencher é opcional" do
      get teacher_organisation_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Preencher é opcional")
    end
  end

  describe "PATCH" do
    before { sign_in teacher }

    it "salva e avisa o que ainda falta" do
      patch teacher_organisation_path, params: { user: { org_name: "Mon OF" } }

      expect(teacher.reload.org_name).to eq("Mon OF")
      expect(flash[:notice]).to include("Ainda falta")
      expect(flash[:notice]).to include("SIRET")
    end

    it "avisa quando fica completo" do
      patch teacher_organisation_path, params: { user: dados_completos }

      expect(teacher.reload).to be_organisme_complete
      expect(flash[:notice]).to include("já saem completas")
    end

    # O ponto do checksum: o SIRET errado não pode ser salvo e depois aparecer
    # no PDF. Ele para aqui.
    it "recusa SIRET com dígito trocado e devolve o formulário" do
      patch teacher_organisation_path, params: { user: { org_siret: "85194793700014" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(teacher.reload.org_siret).to be_nil
      expect(flash.now[:alert]).to include("verificação")
    end

    it "não deixa mexer em campo que não é do organismo" do
      expect {
        patch teacher_organisation_path, params: { user: { role: "admin", org_name: "Mon OF" } }
      }.not_to change { teacher.reload.role }
    end
  end

  describe "a atestação" do
    let(:student)  { create(:user, :student, invited_by_id: teacher.id) }
    let(:activity) { create(:activity, teacher: teacher, level: "A2") }

    before do
      create(:quiz_attempt, user: student, activity: activity,
             started_at: 30.minutes.ago, submitted_at: Time.current)
      sign_in teacher
    end

    context "com o organismo incompleto" do
      it "sai marcada como documento que não pode ser transmitido" do
        get teacher_student_attestation_path(student)

        expect(response.body).to include("Document incomplet")
        expect(response.body).to include("ne pas transmettre")
      end

      it "aponta para a tela que resolve" do
        get teacher_student_attestation_path(student)
        expect(response.body).to include(teacher_organisation_path)
      end
    end

    context "com o organismo completo" do
      before { teacher.update!(dados_completos) }

      it "não traz mais o aviso" do
        get teacher_student_attestation_path(student)
        expect(response.body).not_to include("Document incomplet")
      end

      it "traz a identidade legal de quem emite" do
        get teacher_student_attestation_path(student)

        expect(response.body).to include("Mon Organisme de Formation")
        expect(response.body).to include("851 947 937 00013")
        expect(response.body).to include("11 75 12345 75")
        expect(response.body).to include("Portugais brésilien")
        expect(response.body).to include("Marie Dupont, gérante")
      end

      # Citar o NDA num documento obriga a acompanhá-lo desta frase.
      it "traz a menção obrigatória sobre o registro" do
        get teacher_student_attestation_path(student)
        expect(response.body).to include("ne vaut pas agrément de l'État")
      end

      # O Practice-BR emitia o documento; agora ele só o gera. A diferença é o
      # desenho inteiro do modelo B.
      it "apresenta o Practice-BR como ferramenta, não como emissor" do
        get teacher_student_attestation_path(student)

        expect(response.body).to include("Document généré via la plateforme Practice-BR")
        expect(response.body).not_to include("générée automatiquement par la plateforme")
      end

      # A medição de tempo não mudou nesta frente, e a nota de rodapé continua
      # descrevendo o que o código realmente faz. Este teste cai de propósito se
      # alguém "melhorar" o texto sem melhorar a medição.
      it "continua honesta sobre como o tempo é medido" do
        get teacher_student_attestation_path(student)
        expect(response.body).to include("entre l'ouverture et la soumission")
      end
    end
  end
end
