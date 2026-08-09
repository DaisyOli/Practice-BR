# A ofensiva é o número que o aluno vê na navbar e na dashboard. Se ela mentir,
# mente todo dia — daí testar as bordas com carinho, sobretudo o escudo semanal:
# a regra que decide se um imprevisto apaga três semanas de esforço.
require 'rails_helper'

RSpec.describe User, "#current_streak" do
  include ActiveSupport::Testing::TimeHelpers

  let(:teacher)  { create(:user, :teacher) }
  let(:activity) { create(:activity, teacher: teacher) }
  let(:student)  { create(:user, :student) }
  let(:today)    { Time.zone.today }

  # Cria uma tentativa em cada dia pedido, contado em dias atrás a partir de hoje.
  def praticou_em(*dias_atras)
    dias_atras.each do |dias|
      create(:quiz_attempt,
             user: student,
             activity: activity,
             submitted_at: (today - dias).midday)
    end
    student.reload
  end

  it "é zero para quem nunca praticou" do
    expect(student.current_streak).to eq(0)
  end

  it "conta um dia para quem praticou só hoje" do
    praticou_em(0)
    expect(student.current_streak).to eq(1)
  end

  it "conta dias seguidos" do
    praticou_em(0, 1, 2, 3)
    expect(student.current_streak).to eq(4)
  end

  it "conta várias atividades no mesmo dia como um dia só" do
    praticou_em(0, 0, 0)
    expect(student.current_streak).to eq(1)
  end

  # Hoje ainda não acabou. Quem praticou ontem e ainda não sentou hoje não pode
  # ser punido às 9h da manhã.
  it "não quebra a ofensiva por hoje ainda não ter praticado" do
    praticou_em(1, 2, 3)
    expect(student.current_streak).to eq(3)
  end

  describe "escudo semanal" do
    it "perdoa uma falta e mantém a contagem" do
      # praticou hoje, ontem, faltou anteontem, praticou há 3 dias
      praticou_em(0, 1, 3)
      expect(student.current_streak).to eq(3)
    end

    it "quebra na segunda falta da mesma semana" do
      # duas faltas seguidas gastam o escudo e derrubam
      praticou_em(0, 3)
      expect(student.current_streak).to eq(1)
    end

    # A data fica travada num domingo (fim da semana ISO) porque o resultado
    # depende de onde caem as fronteiras de semana — sem isso o teste passaria
    # ou falharia conforme o dia em que fosse rodado.
    it "devolve o escudo a cada semana do calendário" do
      travel_to Time.zone.local(2026, 8, 2, 12, 0) do # domingo
        # Semana atual: seg 27/07 a dom 02/08 — falta na quinta 30/07.
        # Semana anterior: seg 20/07 a dom 26/07 — falta no domingo 26/07.
        [0, 1, 2, 4, 5, 6, 8, 9].each do |dias|
          create(:quiz_attempt,
                 user: student,
                 activity: activity,
                 submitted_at: (Time.zone.today - dias).midday)
        end

        # Oito dias praticados, dois buracos, um escudo em cada semana.
        expect(student.reload.current_streak).to eq(8)
      end
    end
  end

  it "é zero para quem sumiu faz tempo" do
    praticou_em(20, 21, 22)
    expect(student.current_streak).to eq(0)
  end

  it "usa created_at quando submitted_at está vazio" do
    attempt = create(:quiz_attempt, user: student, activity: activity)
    attempt.update_columns(submitted_at: nil, created_at: today.midday)

    expect(student.reload.current_streak).to eq(1)
  end

  describe "#last_practice_on" do
    it "devolve o dia mais recente de prática" do
      praticou_em(0, 5, 9)
      expect(student.last_practice_on).to eq(today)
    end

    it "é nil para quem nunca praticou" do
      expect(student.last_practice_on).to be_nil
    end
  end
end
