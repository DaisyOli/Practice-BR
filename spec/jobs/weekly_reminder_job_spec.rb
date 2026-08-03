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

  # Antes não havia teto nenhum: quem passava semanas sem entrar recebia a lista
  # inteira do nível. Uma lista longa não convida, intimida — foi o que a Daisy
  # viu chegando no próprio email em 03/08/2026.
  describe "teto de #{described_class::MAX_ACTIVITIES} atividades" do
    it "manda no máximo #{described_class::MAX_ACTIVITIES}, mesmo com muitas pendentes" do
      create(:user, :student, weekly_reminder_email: true, level: "B1")
      create_list(:activity, 12, :B1, draft: false)

      expect { described_class.perform_now }
        .to have_enqueued_mail(StudentMailer, :weekly_reminder)
        .with { |_student, pending, _featured|
          expect(pending.size).to eq(described_class::MAX_ACTIVITIES)
        }
    end

    it "manda as mais recentes, não umas quaisquer" do
      create(:user, :student, weekly_reminder_email: true, level: "B1")
      antigas  = create_list(:activity, 5, :B1, draft: false, created_at: 1.year.ago)
      recentes = create_list(:activity, 5, :B1, draft: false, created_at: 1.day.ago)

      expect { described_class.perform_now }
        .to have_enqueued_mail(StudentMailer, :weekly_reminder)
        .with { |_student, pending, _featured|
          expect(pending.map(&:id)).to match_array(recentes.map(&:id))
          expect(pending.map(&:id)).not_to include(*antigas.map(&:id))
        }
    end

    it "não infla a lista quando há poucas pendentes" do
      create(:user, :student, weekly_reminder_email: true, level: "B1")
      create_list(:activity, 2, :B1, draft: false)

      expect { described_class.perform_now }
        .to have_enqueued_mail(StudentMailer, :weekly_reminder)
        .with { |_student, pending, featured|
          expect(pending.size + featured.size).to be <= described_class::MAX_ACTIVITIES
        }
    end
  end

  it 'envia atividades pendentes do nível do aluno para quem ativou o lembrete' do
    create(:user, :student, weekly_reminder_email: true, level: "B1")
    create(:activity, :B1, draft: false)

    expect {
      described_class.perform_now
    }.to have_enqueued_mail(StudentMailer, :weekly_reminder)
  end

  it 'alcança aluno novo sem ninguém precisar ligar nada' do
    # O lembrete nascia desligado, e quem vem da landing nunca vê caixa nenhuma
    # pra marcar — então o único contato semanal da plataforma simplesmente não
    # acontecia. Repare que a factory não passa `weekly_reminder_email`: quem
    # liga é o default da coluna.
    create(:user, :student, level: "B1")
    create(:activity, :B1, draft: false)

    expect {
      described_class.perform_now
    }.to have_enqueued_mail(StudentMailer, :weekly_reminder)
  end

  it 'respeita quem desligou na dashboard' do
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
