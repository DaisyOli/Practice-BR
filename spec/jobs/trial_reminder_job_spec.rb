require 'rails_helper'

# O lembrete do 3º dia passou a ser só de quem COMEÇOU (2026-08-01). Ele diz
# "você começou, ainda tem atividades" — dizer isso a quem tem zero atividades
# era falar com a pessoa errada, e eram 4 de 5. Essa pessoa recebe o email de
# ativação do TrialSequenceJob.
RSpec.describe TrialReminderJob, type: :job do
  it 'envia o lembrete para quem começou, ainda ativo e sem lembrete enviado' do
    user = create(:user, :trial, created_at: 3.days.ago, trial_expires_at: 4.days.from_now,
                                 trial_activities_used: 1)

    expect {
      described_class.perform_now
    }.to change { ActionMailer::Base.deliveries.count }.by(1)

    expect(user.reload.trial_reminder_sent_at).to be_present
  end

  it 'não fala de "continuar" com quem nunca começou' do
    create(:user, :trial, created_at: 3.days.ago, trial_expires_at: 4.days.from_now,
                          trial_activities_used: 0)

    expect {
      described_class.perform_now
    }.not_to change { ActionMailer::Base.deliveries.count }
  end

  it 'não envia para trials com menos de 3 dias' do
    create(:user, :trial, created_at: 1.day.ago, trial_expires_at: 6.days.from_now,
                          trial_activities_used: 1)

    expect {
      described_class.perform_now
    }.not_to change { ActionMailer::Base.deliveries.count }
  end

  it 'não envia de novo para trials que já receberam o lembrete' do
    create(:user, :trial, created_at: 3.days.ago, trial_expires_at: 4.days.from_now,
                          trial_activities_used: 1, trial_reminder_sent_at: 1.hour.ago)

    expect {
      described_class.perform_now
    }.not_to change { ActionMailer::Base.deliveries.count }
  end

  it 'não envia para trials já expirados' do
    create(:user, :trial, created_at: 8.days.ago, trial_expires_at: 1.day.ago,
                          trial_activities_used: 1)

    expect {
      described_class.perform_now
    }.not_to change { ActionMailer::Base.deliveries.count }
  end

  it 'fala na língua de quem lê' do
    create(:user, :trial, created_at: 3.days.ago, trial_expires_at: 4.days.from_now,
                          trial_activities_used: 1, language: "fr")

    described_class.perform_now

    # Estava inteiro em português fixo, inclusive o assunto, inclusive pra
    # francês — e era o único email que essas pessoas recebiam.
    expect(ActionMailer::Base.deliveries.last.subject).to include("Il vous reste des activités")
  end
end
