# O presenter carrega a conta que antes vivia no topo de dashboard.html.erb.
# Testar aqui é o que torna a refatoração segura: se a view voltar a mentir um
# número de progresso, quebra neste arquivo e não na tela do aluno.
require 'rails_helper'

RSpec.describe StudentDashboardPresenter do
  let(:teacher) { create(:user, :teacher) }
  let(:student) { create(:user, :student, level: 'B1') }

  let!(:a1) { create(:activity, teacher: teacher, level: 'A1') }
  let!(:a2) { create(:activity, teacher: teacher, level: 'A2') }
  let!(:b1) { create(:activity, teacher: teacher, level: 'B1') }

  let(:by_level) { { 'A1' => [a1], 'A2' => [a2], 'B1' => [b1] } }

  def presenter(completed: [], level_filter: nil)
    described_class.new(
      user: student,
      activities_by_level: by_level,
      completed_ids: completed,
      level_filter: level_filter
    )
  end

  describe "#levels_data" do
    it "cobre os cinco níveis, mesmo os vazios" do
      expect(presenter.levels_data.map { |d| d[:level] }).to eq(User::CEFR_LEVELS)
    end

    it "marca como vazio o nível sem atividade" do
      vazio = presenter.levels_data.find { |d| d[:level] == 'C1' }
      expect(vazio[:empty]).to be(true)
      expect(vazio[:pct]).to eq(0)
    end

    it "calcula a porcentagem do nível" do
      dados = presenter(completed: [a1.id]).levels_data.find { |d| d[:level] == 'A1' }
      expect(dados[:done]).to eq(1)
      expect(dados[:pct]).to eq(100)
    end
  end

  describe "#overall_pct" do
    it "é zero quando nada foi feito" do
      expect(presenter.overall_pct).to eq(0)
    end

    it "conta sobre o total de atividades, não sobre o nível" do
      expect(presenter(completed: [a1.id, a2.id]).overall_pct).to eq(67)
    end

    # Aluno novo, base sem atividade nenhuma: dividir por zero aqui era o tipo
    # de bug que só aparece no primeiro dia de um professor novo.
    it "não explode quando não há atividade nenhuma" do
      vazio = described_class.new(user: student, activities_by_level: {}, completed_ids: [])
      expect(vazio.overall_pct).to eq(0)
      expect(vazio.total_completed).to eq(0)
    end
  end

  describe "#continue_activity" do
    it "sugere uma atividade que o aluno ainda não fez" do
      sugerida = presenter.continue_activity
      expect(sugerida).to be_present
      expect(sugerida.id).not_to eq(nil)
    end

    it "não sugere nada quando o aluno filtrou por nível" do
      expect(presenter(level_filter: 'A1').continue_activity).to be_nil
    end

    it "não sugere atividade já concluída" do
      todas = [a1.id, a2.id, b1.id]
      expect(presenter(completed: todas).continue_activity).to be_nil
    end
  end

  describe "#last_completed_activity" do
    it "é nil enquanto ainda há coisa pendente" do
      expect(presenter.last_completed_activity).to be_nil
    end

    it "mostra a última feita quando não sobrou nada pendente" do
      create(:quiz_attempt, user: student, activity: b1, submitted_at: 1.hour.ago)

      resultado = presenter(completed: [a1.id, a2.id, b1.id]).last_completed_activity
      expect(resultado&.id).to eq(b1.id)
    end
  end
end
