require 'rails_helper'

# A série de pílulas no caminho do aluno (pedido da Daisy, 18/11/2026, com a
# série da Chu Ming): a parte 1 é sempre a primeira oferecida, a continuação é
# um convite sem obrigação ("Conheça a continuação") e o fim da série tem festa.
RSpec.describe "Série de pílulas: o caminho do aluno", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:teacher) { create(:user, :teacher) }
  let(:aluno)   { create(:user, :student, level: "B1") }

  def parte(posicao, chave: "video-chu-ming", **attrs)
    create(:activity, :B1, teacher: teacher, draft: false, pill: true,
                           series_key: chave, series_position: posicao,
                           title: "A invenção do orelhão: parte #{posicao}", **attrs)
  end

  def fazer(atividade)
    questao = atividade.questions.first || create(:question, :multiple_choice, activity: atividade)
    post submit_activity_path(atividade), params: { answers: { questao.id.to_s => "Brasília" } }
  end

  # As três criadas juntas, como a geração cria: a parte 3 é a mais nova.
  let!(:p1) { parte(1, video_url: "https://youtu.be/abcdefghijk") }
  let!(:p2) { parte(2, video_url: "https://youtu.be/abcdefghijk") }
  let!(:p3) { parte(3, video_url: "https://youtu.be/abcdefghijk") }

  describe "Activity#series_entry_for" do
    it "entra pela primeira parte que a pessoa ainda não fez" do
      expect(p3.series_entry_for([])).to eq(p1)
      expect(p3.series_entry_for([p1.id])).to eq(p2)
      expect(p1.series_entry_for([p1.id, p3.id])).to eq(p2)
      expect(p2.series_entry_for([p1.id, p2.id, p3.id])).to eq(p2)
    end

    it "fora de série devolve a própria atividade" do
      solta = create(:activity, :B1, draft: false)
      expect(solta.series_entry_for([])).to eq(solta)
    end

    it "pula a parte em rascunho" do
      p1.update!(draft: true)
      expect(p3.series_entry_for([])).to eq(p2)
    end
  end

  describe "quem sugere atividade nunca começa pela parte 2 ou 3" do
    it "\"Comece por aqui\": a mais nova publicada é a parte 3, mas a oferta é a parte 1" do
      pessoa = create(:user, :trial, level: "B1")

      expect(pessoa.suggested_first_activity).to eq(p1)
    end

    it "percurso com a parte 2: entra pela parte 1" do
      Activity.set_path!("B1", [p2.id])

      expect(aluno.next_path_activity).to eq(p1)
    end

    it "o sorteio do painel que cairia na parte 3 oferece a parte 1" do
      presenter = StudentDashboardPresenter.new(user: aluno, activities_by_level: { "B1" => [p3, p2, p1] },
                                                completed_ids: [])

      expect(presenter.continue_activity).to eq(p1)
      expect(presenter.series_continuation?).to be(false)
    end

    it "o email de \"sentimos sua falta\" oferece a parte 1" do
      expect(InactivityNudgeJob.new.send(:next_activity_for, aluno)).to eq(p1)
    end

    it "o lembrete semanal lista a série uma vez só, pela parte 1" do
      aluno.update!(weekly_reminder_email: true)
      allow(Date).to receive(:current).and_return(Date.new(2026, 11, 16)) # segunda

      expect { WeeklyReminderJob.perform_now }
        .to have_enqueued_mail(StudentMailer, :weekly_reminder)
        .with { |_aluno, pendentes, _destaques| expect(pendentes).to eq([p1]) }
    end
  end

  describe "depois da parte 1" do
    before do
      sign_in aluno
      fazer(p1)
    end

    it "a nota já conta que a história continua, sem botão" do
      follow_redirect!

      expect(response.body).to include("🎬 A história continua na Parte 2 de 3", "A invenção do orelhão: parte 2")
      expect(response.body).not_to include("Série completa")
    end

    it "o fim do resultado convida: Conheça a continuação, sem obrigação" do
      get results_activity_path(p1)

      expect(response.body).to include("🎬 Conheça a continuação · Parte 2 de 3", "Continuar →",
                                       "Prefiro escolher outra atividade")
    end

    it "o painel oferece a parte 2 como continuação" do
      get student_dashboard_path

      cartao = response.body[response.body.index('id="tour-continue"'), 4000]
      expect(cartao).to include("A invenção do orelhão: parte 2", "🎬 Continuação · Parte 2 de 3")
    end
  end

  describe "o fim da série" do
    before { sign_in aluno }

    it "festa quando a última parte fecha a série" do
      fazer(p1)
      fazer(p2)
      fazer(p3)
      follow_redirect!

      expect(response.body).to include("🎉 Série completa!", "Você viu o vídeo inteiro em 3 pílulas.")
    end

    it "sem vídeo, a festa fala das partes" do
      [p1, p2, p3].each { |p| p.update!(video_url: nil) }
      [p1, p2, p3].each { |p| fazer(p) }
      follow_redirect!

      expect(response.body).to include("Você fez as 3 partes da série.")
    end

    it "fez a 3 antes da 1: a nota lembra o que falta" do
      fazer(p3)
      follow_redirect!

      expect(response.body).to include("🎬 Ainda falta a Parte 1 de 3")
      expect(response.body).not_to include("Série completa")
    end
  end

  describe "abrir uma parte fora de ordem" do
    before { sign_in aluno }

    it "a parte 2 sem a 1: aviso leve com o caminho para a parte 1, sem trava" do
      get solve_activity_path(p2)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("A história começa na Parte 1 de 3", solve_activity_path(p1))
    end

    it "com a parte 1 feita, nenhum aviso" do
      fazer(p1)
      get solve_activity_path(p2)

      expect(response.body).not_to include("A história começa")
    end
  end

  describe "na lista do nível" do
    before { sign_in aluno }

    it "as partes aparecem juntas, em ordem, com o selo de cada uma" do
      antiga = create(:activity, :B1, draft: false, title: "Atividade antiga", created_at: 2.days.ago)

      lista = Activity.published.by_level("B1").in_student_order.to_a
      expect(lista).to eq([p1, p2, p3, antiga])

      get student_dashboard_path(level: "B1")
      expect(response.body).to include("✂️ Parte 1 de 3")
    end

    it "a próxima atividade de outra série não se diz continuação" do
      outra = parte(1, chave: "video-outra", title: "Outra história: começo")
      parte(2, chave: "video-outra", title: "Outra história: fim")
      solta = create(:activity, :B1, draft: false)
      questao = create(:question, :multiple_choice, activity: solta)
      Activity.set_path!("B1", [outra.id])
      post submit_activity_path(solta), params: { answers: { questao.id.to_s => "Brasília" } }

      get results_activity_path(solta)

      expect(response.body).to include("Próxima atividade 🌱 · B1 · ✂️ Parte 1 de 2", "Outra história: começo")
      expect(response.body).not_to include("Conheça a continuação")
    end
  end

  it "os dois prompts de série pedem o mesmo nome da série no começo de cada título" do
    regra = "começa pelo MESMO nome curto da série"
    expect(AdaptIntoPillsService::INSTRUCTIONS).to include(regra)
    expect(ActivityFromVideoService.new(youtube_url: "https://youtu.be/abcdefghijk", transcript: "0:00 Olá",
                                        teacher: teacher).build_prompt).to include(regra)
  end
end
