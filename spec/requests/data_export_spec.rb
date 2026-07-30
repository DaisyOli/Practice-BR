require 'rails_helper'

# Direito de acesso e de portabilidade (RGPD arts. 15 e 20 · LGPD art. 18).
#
# A spec que mais importa aqui é a última: se uma tabela nova passar a guardar
# dado de pessoa e ninguém lembrar de incluir na exportação, o direito fica
# incompleto sem ninguém perceber.
RSpec.describe "Exportação de dados", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:aluno) do
    create(:user, :student,
           name: "Camille", level: "B2",
           stripe_customer_id: "cus_123", subscription_status: "active")
  end
  let(:atividade) { create(:activity, :B2, title: "Feira livre", draft: false) }

  def exportado
    JSON.parse(response.body)
  end

  describe "GET /meus-dados" do
    it "mostra o resumo do que guardamos" do
      sign_in aluno
      get data_export_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Seus dados")
      expect(response.body).to include("Atividades respondidas")
    end

    it "exige login" do
      get data_export_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "GET /meus-dados/download" do
    before { sign_in aluno }

    it "entrega um JSON como anexo, com nome de arquivo datado" do
      get data_export_download_path

      expect(response.media_type).to eq("application/json")
      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(response.headers["Content-Disposition"]).to include("practice-br-meus-dados-#{Date.current.iso8601}.json")
    end

    it "traz os dados da conta" do
      get data_export_download_path

      conta = exportado["conta"]
      expect(conta["email"]).to eq(aluno.email)
      expect(conta["nome"]).to eq("Camille")
      expect(conta["nivel"]).to eq("B2")
    end

    it "NUNCA inclui a senha, nem o hash, nem tokens de recuperação" do
      aluno.update!(reset_password_token: "token-secreto-123")

      get data_export_download_path

      expect(response.body).not_to include(aluno.encrypted_password)
      expect(response.body).not_to include("token-secreto-123")
      expect(response.body.downcase).not_to include("encrypted_password")
    end

    it "traz as respostas dos exercícios, que é o que a portabilidade pede" do
      create(:quiz_attempt, user: aluno, activity: atividade, score: 90.0)

      get data_export_download_path

      tentativa = exportado["atividades_respondidas"].first
      expect(tentativa["atividade"]).to eq("Feira livre")
      expect(tentativa["nota"]).to eq(90.0)
      expect(tentativa["respostas"]).to be_present
    end

    it "traz o texto das respostas faladas" do
      AudioTranscription.create!(user: aluno, status: "done", text: "Eu fui à feira ontem")

      get data_export_download_path

      expect(exportado["respostas_em_audio"].first["texto_transcrito"]).to eq("Eu fui à feira ontem")
    end

    it "traz as avaliações que a pessoa deu" do
      create(:activity_rating, user: aluno, activity: atividade, stars: 4, comment: "gostei")

      get data_export_download_path

      avaliacao = exportado["avaliacoes_que_voce_deu"].first
      expect(avaliacao["estrelas"]).to eq(4)
      expect(avaliacao["comentario"]).to eq("gostei")
    end

    it "registra a existência da notificação mas não a credencial" do
      create(:push_subscription, user: aluno, endpoint: "https://push.exemplo/abc", auth_key: "chave-secreta")

      get data_export_download_path

      expect(exportado["notificacoes"].size).to eq(1)
      expect(response.body).not_to include("chave-secreta")
      expect(response.body).not_to include("https://push.exemplo/abc")
    end

    it "não inventa seção de assinatura pra quem nunca pagou" do
      sign_in create(:user, :trial)
      get data_export_download_path

      expect(exportado).not_to have_key("assinatura")
    end

    it "só entrega os dados de quem está logado" do
      outro = create(:user, :student, name: "Outra Pessoa")
      create(:quiz_attempt, user: outro, activity: atividade)

      get data_export_download_path

      expect(response.body).not_to include(outro.email)
      expect(response.body).not_to include("Outra Pessoa")
      expect(exportado["atividades_respondidas"]).to be_empty
    end

    it "inclui as atividades criadas quando é professora" do
      professora = create(:user, :teacher)
      create(:activity, teacher: professora, title: "Minha atividade")
      sign_in professora

      get data_export_download_path

      expect(exportado["atividades_criadas"].first["titulo"]).to eq("Minha atividade")
    end

    it "exige login" do
      sign_out aluno
      get data_export_download_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "cobertura das tabelas" do
    it "exporta algo de toda tabela que guarda dado ligado a uma pessoa" do
      # Guarda-chuva contra esquecimento: se alguém criar uma tabela nova com
      # user_id e não incluir na exportação, esta spec falha e explica o que fazer.
      tabelas_com_dono = ActiveRecord::Base.connection.tables.select do |t|
        ActiveRecord::Base.connection.columns(t).map(&:name).include?("user_id")
      end

      cobertas = {
        "quiz_attempts"        => :atividades_respondidas,
        "audio_transcriptions" => :respostas_em_audio,
        "activity_ratings"     => :avaliacoes_que_voce_deu,
        "push_subscriptions"   => :notificacoes
      }

      esquecidas = tabelas_com_dono - cobertas.keys
      expect(esquecidas).to be_empty,
        "Tabela(s) com user_id fora da exportação: #{esquecidas.join(', ')}. " \
        "Inclua em DataExportService (e confira o dependent: :destroy pra exclusão)."
    end
  end
end
