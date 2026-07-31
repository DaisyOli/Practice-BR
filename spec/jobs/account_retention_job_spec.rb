require 'rails_helper'

# Este é o job que apaga conta de gente. Os testes aqui não estão medindo só
# "funciona": metade deles existe pra provar que ele NÃO apaga quem não deve.
RSpec.describe AccountRetentionJob, type: :job do
  # Um aluno parado há tempo suficiente pra estar no prazo, mas ainda não avisado.
  def stale_student(inactive_for: 3.years + 1.month, **attrs)
    create(:user, :student, created_at: inactive_for.ago, **attrs)
  end

  describe 'aviso' do
    it 'avisa o aluno inativo em vez de apagar de cara' do
      user = stale_student

      expect {
        described_class.perform_now
      }.to change { ActionMailer::Base.deliveries.count }.by(1)

      expect(User.exists?(user.id)).to be true
      expect(user.reload.retention_warning_sent_at).to be_present
    end

    it 'avisa quando faltam menos de 30 dias para o prazo, não antes' do
      # 3 anos menos 10 dias: dentro da janela de aviso.
      user = stale_student(inactive_for: 3.years - 10.days)

      expect { described_class.perform_now }.to change { ActionMailer::Base.deliveries.count }.by(1)
      expect(user.reload.retention_warning_sent_at).to be_present
    end

    it 'não avisa quem ainda está longe do prazo' do
      user = stale_student(inactive_for: 2.years)

      expect { described_class.perform_now }.not_to change { ActionMailer::Base.deliveries.count }
      expect(user.reload.retention_warning_sent_at).to be_nil
    end

    it 'não reenvia o aviso todo dia' do
      stale_student(retention_warning_sent_at: 2.days.ago)

      expect { described_class.perform_now }.not_to change { ActionMailer::Base.deliveries.count }
    end

    it 'manda o aviso no idioma da pessoa' do
      stale_student(language: 'fr')
      described_class.perform_now

      expect(ActionMailer::Base.deliveries.last.subject).to include('sera supprimé')
    end
  end

  describe 'exclusão' do
    it 'apaga quem foi avisado e deixou a carência inteira passar' do
      user = stale_student(retention_warning_sent_at: 31.days.ago)

      described_class.perform_now

      expect(User.exists?(user.id)).to be false
    end

    it 'não apaga quem foi avisado ontem, mesmo com o prazo vencido' do
      user = stale_student(retention_warning_sent_at: 1.day.ago)

      described_class.perform_now

      expect(User.exists?(user.id)).to be true
    end

    it 'leva junto o histórico de atividades' do
      user     = stale_student(retention_warning_sent_at: 31.days.ago)
      activity = create(:activity)
      create(:quiz_attempt, user: user, activity: activity, created_at: 3.years.ago)

      expect { described_class.perform_now }.to change { QuizAttempt.count }.by(-1)
      expect(User.exists?(user.id)).to be false
    end
  end

  describe 'quem nunca é apagado' do
    it 'ignora a professora, por mais parada que a conta esteja' do
      teacher = create(:user, :teacher, created_at: 5.years.ago)

      described_class.perform_now

      expect(User.exists?(teacher.id)).to be true
      expect(teacher.reload.retention_warning_sent_at).to be_nil
    end

    it 'ignora admin' do
      admin = create(:user, :admin, created_at: 5.years.ago)

      described_class.perform_now

      expect(User.exists?(admin.id)).to be true
    end

    it 'ignora quem tem assinatura em curso, mesmo sem praticar há anos' do
      %w[active canceling past_due].each do |status|
        user = stale_student(retention_warning_sent_at: 31.days.ago,
                             subscription_status: status,
                             stripe_customer_id: "cus_#{status}")

        described_class.perform_now

        expect(User.exists?(user.id)).to be(true), "assinatura #{status} deveria segurar a conta"
      end
    end
  end

  describe 'quando a pessoa volta' do
    it 'limpa o aviso de quem praticou de novo' do
      user     = stale_student(retention_warning_sent_at: 31.days.ago)
      activity = create(:activity)
      create(:quiz_attempt, user: user, activity: activity, created_at: Time.current)

      described_class.perform_now

      expect(User.exists?(user.id)).to be true
      expect(user.reload.retention_warning_sent_at).to be_nil
    end
  end

  describe 'trials' do
    it 'apaga trial não convertido 12 meses depois de o teste expirar' do
      user = create(:user, :trial, trial_expires_at: 13.months.ago,
                                   retention_warning_sent_at: 31.days.ago)

      described_class.perform_now

      expect(User.exists?(user.id)).to be false
    end

    it 'não apaga trial que ainda está dentro dos 12 meses' do
      user = create(:user, :trial, trial_expires_at: 3.months.ago)

      described_class.perform_now

      expect(User.exists?(user.id)).to be true
    end

    # A armadilha: o papel volta pra `trial` quando a assinatura é cancelada, e
    # o trial_expires_at continua sendo o do teste original, de anos atrás. Sem
    # o `never_converted_trial?`, um ex-aluno pagante seria apagado pelo prazo de
    # quem nunca pagou — 12 meses em vez de 3 anos.
    it 'não trata ex-pagante rebaixado a trial como trial não convertido' do
      user = create(:user, :trial, trial_expires_at: 2.years.ago,
                                   stripe_customer_id: 'cus_ja_pagou',
                                   subscription_status: 'canceled',
                                   created_at: 2.years.ago,
                                   retention_warning_sent_at: 31.days.ago)

      described_class.perform_now

      expect(User.exists?(user.id)).to be true
    end
  end

  describe 'falhas' do
    it 'uma conta que falha não impede as outras de serem apagadas' do
      quebrada = stale_student(retention_warning_sent_at: 31.days.ago)
      ok       = stale_student(retention_warning_sent_at: 31.days.ago)

      allow(AccountDeletionService).to receive(:new).and_call_original
      allow(AccountDeletionService).to receive(:new).with(
        satisfy { |u| u.id == quebrada.id }, any_args
      ).and_return(instance_double(AccountDeletionService).tap do |double|
        allow(double).to receive(:call).and_raise(Stripe::StripeError.new('recusado'))
      end)

      described_class.perform_now

      expect(User.exists?(quebrada.id)).to be true
      expect(User.exists?(ok.id)).to be false
    end
  end
end
