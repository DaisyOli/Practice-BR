require 'rails_helper'

RSpec.describe WeeklyReminderJob, type: :job do
  let(:monday) { Date.new(2026, 7, 27) }

  before { allow(Date).to receive(:current).and_return(monday) }

  it 'não envia nada se hoje não for segunda-feira' do
    allow(Date).to receive(:current).and_return(monday - 1.day)
    create(:user, :student, weekly_reminder_email: true, level: "B1")
    create(:activity, :B1, draft: false)

    expect {
      described_class.perform_now
    }.not_to have_enqueued_mail(StudentMailer, :weekly_reminder)
  end

  it 'envia atividades pendentes do nível do aluno para quem ativou o lembrete' do
    create(:user, :student, weekly_reminder_email: true, level: "B1")
    create(:activity, :B1, draft: false)

    expect {
      described_class.perform_now
    }.to have_enqueued_mail(StudentMailer, :weekly_reminder)
  end

  it 'não envia para quem não ativou o lembrete' do
    create(:user, :student, weekly_reminder_email: false, level: "B1")
    create(:activity, :B1, draft: false)

    expect {
      described_class.perform_now
    }.not_to have_enqueued_mail(StudentMailer, :weekly_reminder)
  end

  it 'não envia se o aluno já completou todas as atividades pendentes e não há destaque' do
    student = create(:user, :student, weekly_reminder_email: true, level: "B1")
    activity = create(:activity, :B1, draft: false)
    create(:quiz_attempt, user: student, activity: activity)

    expect {
      described_class.perform_now
    }.not_to have_enqueued_mail(StudentMailer, :weekly_reminder)
  end

  it 'não envia para alunos sem nível definido' do
    # Todo aluno tem nível — o model valida isso. Este caso só existe se um dado
    # torto entrar por importação ou console, e o job precisa aguentar: daí o
    # update_columns, que grava sem passar pela validação.
    aluno = create(:user, :student, weekly_reminder_email: true)
    aluno.update_columns(level: nil)
    create(:activity, :B1, draft: false)

    expect {
      described_class.perform_now
    }.not_to have_enqueued_mail(StudentMailer, :weekly_reminder)
  end

  it 'não explode ao serializar as atividades pendentes via deliver_later (bug do ActiveRecord::Relation)' do
    create(:user, :student, weekly_reminder_email: true, level: "B1")
    create(:activity, :B1, draft: false)

    expect { described_class.perform_now }.not_to raise_error
  end
end
