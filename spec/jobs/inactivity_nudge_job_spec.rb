require 'rails_helper'

# Este job existia e não acontecia. Até 2026-08-01 ele só mandava push, e a base
# tinha zero inscrições de push: rodava a cada 6 horas olhando pra uma lista
# vazia enquanto alunos passavam uma semana fora sem receber nada. O email é o
# canal que comprovadamente chega; o push ficou junto, pra quem um dia ativar.
RSpec.describe InactivityNudgeJob, type: :job do
  # Sempre precisa haver algo pendente pra sugerir — sem isso o job não manda
  # nada, de propósito.
  let!(:pendente) { create(:activity, :B1, draft: false) }

  def aluno_sumido(**attrs)
    student = create(:user, :student, level: "B1", **attrs)
    create(:quiz_attempt, user: student, activity: create(:activity, :B1, draft: false),
                          submitted_at: 3.days.ago)
    student
  end

  it 'manda email com uma atividade concreta pra quem sumiu há 48h+' do
    student = aluno_sumido

    expect { described_class.perform_now }
      .to have_enqueued_mail(StudentMailer, :inactivity_nudge).with(student, pendente)

    expect(student.reload.inactivity_nudge_sent_at).to be_present
  end

  it 'avisa mesmo sem push ativo — era exatamente esse o buraco' do
    student = aluno_sumido
    expect(student.push_subscriptions).to be_empty

    expect { described_class.perform_now }
      .to have_enqueued_mail(StudentMailer, :inactivity_nudge)
  end

  it 'manda push junto pra quem tem' do
    student = aluno_sumido
    create(:push_subscription, user: student)

    expect(PushNotificationService).to receive(:send_to_user)
      .with(student, hash_including(title: "Sentimos sua falta!"))

    described_class.perform_now
  end

  it 'usa texto misturado com português para aluno de língua inglesa' do
    student = aluno_sumido(language: "en")
    create(:push_subscription, user: student)

    expect(PushNotificationService).to receive(:send_to_user)
      .with(student, hash_including(title: "We miss you · sentimos sua falta!"))

    described_class.perform_now
  end

  it 'usa texto misturado com português para aluno de língua francesa' do
    student = aluno_sumido(language: "fr")
    create(:push_subscription, user: student)

    expect(PushNotificationService).to receive(:send_to_user)
      .with(student, hash_including(title: "Vous nous manquez · sentimos sua falta !"))

    described_class.perform_now
  end

  it 'respeita quem desligou o lembrete na dashboard' do
    # Um interruptor só: quem pediu pra não ser lembrado não quer receber o
    # mesmo lembrete com outro nome.
    aluno_sumido(weekly_reminder_email: false)

    expect { described_class.perform_now }
      .not_to have_enqueued_mail(StudentMailer, :inactivity_nudge)
  end

  it 'não avisa quem praticou há menos de 48h' do
    student = create(:user, :student, level: "B1")
    create(:quiz_attempt, user: student, submitted_at: 10.hours.ago)

    expect { described_class.perform_now }
      .not_to have_enqueued_mail(StudentMailer, :inactivity_nudge)
  end

  it 'não avisa quem nunca praticou' do
    create(:user, :student, level: "B1")

    expect { described_class.perform_now }
      .not_to have_enqueued_mail(StudentMailer, :inactivity_nudge)
  end

  it 'não manda convite para uma tela vazia quando não há nada pendente' do
    pendente.destroy
    aluno_sumido

    expect { described_class.perform_now }
      .not_to have_enqueued_mail(StudentMailer, :inactivity_nudge)
  end

  it 'não avisa trial — esse tem o TrialReminderJob' do
    trial = create(:user, :trial, level: "B1")
    create(:quiz_attempt, user: trial, submitted_at: 3.days.ago)

    expect { described_class.perform_now }
      .not_to have_enqueued_mail(StudentMailer, :inactivity_nudge)
  end

  it 'não avisa de novo enquanto o aluno não voltar a praticar' do
    aluno_sumido(inactivity_nudge_sent_at: 1.hour.ago)

    expect { described_class.perform_now }
      .not_to have_enqueued_mail(StudentMailer, :inactivity_nudge)
  end

  it 'avisa de novo se o aluno praticou depois do último aviso e sumiu de novo' do
    aluno_sumido(inactivity_nudge_sent_at: 5.days.ago)

    expect { described_class.perform_now }
      .to have_enqueued_mail(StudentMailer, :inactivity_nudge)
  end
end
