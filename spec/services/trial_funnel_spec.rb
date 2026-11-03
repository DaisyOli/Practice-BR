require 'rails_helper'

RSpec.describe TrialFunnel do
  include ActiveSupport::Testing::TimeHelpers

  let!(:atividade) { create(:activity, :B1, draft: false) }
  let(:hoje) { described_class.measured_since + 5.days }

  around { |ex| travel_to(hoje) { ex.run } }

  def trial(**attrs)
    create(:user, :trial, level: "B1", created_at: 1.day.ago, **attrs)
  end

  subject(:stats) { described_class.new(from: 30.days.ago).stats }

  it "conta cada degrau, e um robô que só pede a página não vira gente" do
    trial                                                         # pediu e sumiu
    trial(trial_start_used_at: 1.day.ago)                         # link consumido, nada mais
    trial(first_access_at: 1.day.ago, first_activity_opened_at: 1.day.ago) # robô do email
    trial(first_human_at: 1.day.ago)                              # entrou de verdade
    trial(first_human_at: 1.day.ago, first_activity_human_at: 1.day.ago)
    trial(first_human_at: 1.day.ago, first_activity_human_at: 1.day.ago, first_answer_at: 1.day.ago)
    create(:quiz_attempt, user: trial, activity: atividade)       # concluiu

    expect(stats).to include(requested: 7, link_used: 1, measured: 7, entered: 4,
                             opened_activity: 3, answered: 2, completed_first: 1)
    expect(stats[:activation_rate]).to eq(14.3)
  end

  it "não mistura contas antigas nos degraus medidos: nelas o dado não existe" do
    create(:user, :trial, level: "B1", created_at: described_class.measured_since - 2.days,
                          trial_start_used_at: 10.days.ago)
    trial(first_human_at: 1.day.ago)

    expect(stats).to include(requested: 2, link_used: 1, measured: 1, entered: 1)
  end

  it "conta por onde as contas medidas entraram" do
    trial(first_entry_source: "landing")
    trial(first_entry_source: "landing")
    trial(first_entry_source: "email")

    expect(stats[:by_source]).to eq("landing" => 2, "email" => 1)
  end

  it "conta quem venceu sem fazer nada" do
    trial(trial_expires_at: 1.hour.ago)

    expect(stats[:expired_untouched]).to eq(1)
  end

  it "separa quem ativou antes de qualquer lembrete de quem ativou depois de um" do
    sozinha = trial(created_at: 3.days.ago)
    create(:quiz_attempt, user: sozinha, activity: atividade, created_at: 3.days.ago + 10.minutes)

    lembrada = trial(created_at: 3.days.ago, first_nudge_sent_at: 3.days.ago + 4.hours)
    create(:quiz_attempt, user: lembrada, activity: atividade, created_at: 2.days.ago)

    expect(stats[:activated_after]).to eq("nenhum lembrete" => 1, "mesmo dia (4h)" => 1)
  end

  it "deixa de fora convite de professora e as contas excluídas" do
    trial(invitation_created_at: 1.day.ago)
    teste = trial

    expect(described_class.new(from: 30.days.ago, exclude_ids: [teste.id]).stats[:requested]).to eq(0)
  end
end
