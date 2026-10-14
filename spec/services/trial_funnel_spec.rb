require 'rails_helper'

RSpec.describe TrialFunnel do
  let!(:atividade) { create(:activity, :B1, draft: false) }

  def trial(**attrs)
    create(:user, :trial, level: "B1", created_at: 3.days.ago, **attrs)
  end

  subject(:stats) { described_class.new(from: 10.days.ago).stats }

  it "conta cada degrau do funil a partir do que o banco já guarda" do
    trial                                                           # pediu e sumiu
    trial(first_access_at: 3.days.ago)                              # entrou
    trial(first_access_at: 3.days.ago, first_activity_opened_at: 3.days.ago) # abriu
    ativa = trial(first_access_at: 3.days.ago)                      # concluiu
    create(:quiz_attempt, user: ativa, activity: atividade)

    expect(stats).to include(requested: 4, accessed: 3, opened_activity: 2, completed_first: 1)
    expect(stats[:activation_rate]).to eq(25.0)
  end

  it "conta quem venceu sem fazer nada" do
    trial(trial_expires_at: 1.hour.ago)

    expect(stats[:expired_untouched]).to eq(1)
  end

  it "separa quem ativou antes de qualquer lembrete de quem ativou depois de um" do
    sozinha = trial
    create(:quiz_attempt, user: sozinha, activity: atividade, created_at: 3.days.ago + 10.minutes)

    lembrada = trial(first_nudge_sent_at: 3.days.ago + 4.hours)
    create(:quiz_attempt, user: lembrada, activity: atividade, created_at: 2.days.ago)

    expect(stats[:activated_after]).to eq("nenhum lembrete" => 1, "mesmo dia (4h)" => 1)
  end

  it "deixa de fora convite de professora e as contas excluídas" do
    trial(invitation_created_at: 3.days.ago)
    teste = trial

    expect(described_class.new(from: 10.days.ago, exclude_ids: [teste.id]).stats[:requested]).to eq(0)
  end
end
