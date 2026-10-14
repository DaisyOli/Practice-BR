# Roda de hora em hora, das 8h às 21h de Paris (cron do GoodJob, ver
# config/environments/production.rb). Era uma vez por dia, às 7h30, e isso
# transformava o "D+1" em qualquer coisa entre 24h e 48h — e não deixava espaço
# para um lembrete no mesmo dia. A janela de horário é o que impede email de
# madrugada: quem se cadastra às 23h recebe o lembrete às 8h.
#
# A sequência de emails de quem está testando. Existe por causa de uma medição de
# 2026-08-01: das 5 pessoas reais que tinham entrado no teste, 4 nunca
# responderam UMA questão — e a plataforma mandava um único email, no 3º dia,
# dizendo "continue praticando" para quem nunca praticou. Depois que o teste
# vencia, silêncio: o próximo email possível era o aviso de exclusão de conta,
# 11 meses depois.
#
# Um email por momento, cada um no máximo uma vez na vida da pessoa:
#
#   4h–20h sem ter começado       → mesmo dia (TrialMailer#first_nudge_email)
#   D+1 sem ter começado          → ativação (TrialMailer#activation_email)
#   venceu sem nunca ter começado → reabertura de 7 dias (TrialMailer#reopen_email)
#   fim do teste (esgotou/venceu) → balanço pessoal (TrialMailer#ended_email)
#   +3 dias, se praticou          → a próxima do percurso (TrialMailer#next_step_email)
#   +8 dias                       → a última (TrialMailer#winback_email)
#
# Os três depois do fim são a "Fase B" (2026-10-15): o balanço mostra à pessoa o
# que ela fez, o do meio mostra uma atividade concreta que a assinatura abre, e
# o último promete silêncio. Sem desconto, por decisão da Daisy. Para no
# instante em que a pessoa assina: assinante sai de `candidates`.
#
# O lembrete do 3º dia (TrialReminderJob) continua existindo e agora só fala com
# quem COMEÇOU — os dois não se cruzam.
class TrialSequenceJob < ApplicationJob
  queue_as :default

  FIRST_NUDGE_AFTER = 4.hours
  # Passou disto sem o lembrete do mesmo dia ter saído (cadastro de madrugada,
  # job fora do ar), ele é pulado: chegaria colado no D+1 e viraria dois emails
  # dizendo a mesma coisa.
  FIRST_NUDGE_UNTIL = 20.hours
  ACTIVATION_AFTER  = 1.day
  # Distância mínima entre o lembrete do mesmo dia e o D+1.
  NUDGE_SPACING     = 12.hours
  REOPEN_FOR        = 7.days
  NEXT_STEP_AFTER   = 3.days
  WINBACK_AFTER     = 8.days

  def perform
    candidates.find_each do |trial|
      # No máximo um email por pessoa por rodada. Sem isto, alguém que esgotou o
      # teste no primeiro dia receberia dois emails na mesma manhã.
      send_first_nudge(trial) || send_activation(trial) || send_reopen(trial) ||
        send_ended(trial) || send_next_step(trial) || send_winback(trial)
    end
  end

  private

  # `never_converted_trial?` em vez do papel sozinho: quem cancela a assinatura
  # VOLTA a ser trial, com o trial_expires_at do teste original de meses atrás.
  # Sem este filtro, um ex-aluno pagante receberia a sequência de boas-vindas do
  # teste no dia seguinte ao cancelamento.
  def candidates
    User.trials.where(stripe_customer_id: nil)
  end

  # "Ainda não começou" é zero tentativas, não `trial_activities_used` zero: o
  # contador é do teste, a tentativa é o fato.
  def never_started?(trial)
    trial.trial_activities_used.to_i.zero? && trial.quiz_attempts.none?
  end

  def send_first_nudge(trial)
    return false if trial.first_nudge_sent_at.present?
    return false if trial.trial_reopened_at.present?
    return false unless trial.trial_access_active?
    return false unless never_started?(trial)
    return false if trial.created_at > FIRST_NUDGE_AFTER.ago
    return false if trial.created_at < FIRST_NUDGE_UNTIL.ago

    activity = first_activity_for(trial)
    return false if activity.nil?

    send_once(trial, :first_nudge_sent_at) do
      TrialMailer.first_nudge_email(trial, activity).deliver_later
    end
  end

  # O link do email entra sem senha (TrialEmailLink): antes ele ia direto para a
  # atividade contando com o "lembrar de mim" da landing, e quem abria o email
  # em outro aparelho caía num login sem senha para digitar. Quem já foi
  # reaberto está fora daqui — acabou de receber um link e não precisa de dois
  # emails em dois dias.
  def send_activation(trial)
    return false if trial.activation_nudge_sent_at.present?
    return false if trial.trial_reopened_at.present?
    return false unless trial.trial_access_active?
    return false unless never_started?(trial)
    return false if trial.created_at > ACTIVATION_AFTER.ago
    return false if trial.first_nudge_sent_at&.>(NUDGE_SPACING.ago)

    activity = first_activity_for(trial)
    return false if activity.nil?

    send_once(trial, :activation_nudge_sent_at) do
      TrialMailer.activation_email(trial, activity).deliver_later
    end
  end

  # O teste acabou sem a pessoa abrir uma única atividade. Antes de falar em
  # pagar, devolve o que ela não usou — uma vez só.
  #
  # Reabrir é mais que mudar uma data: quem entrou pela landing nunca criou
  # senha, e o link do email original já venceu. O email leva um link novo
  # (TrialEmailLink), gerado agora e válido por 8 dias — mais que os 7 da
  # reabertura.
  def send_reopen(trial)
    return false if trial.trial_reopened_at.present?
    return false if trial.trial_access_active?
    return false unless never_started?(trial)

    activity = first_activity_for(trial)
    return false if activity.nil?

    send_once(trial, :trial_reopened_at, trial_expires_at: REOPEN_FOR.from_now) do
      TrialMailer.reopen_email(trial.reload, activity).deliver_later
    end
  end

  def send_ended(trial)
    return false if trial.trial_ended_email_sent_at.present?
    return false if trial.trial_access_active?

    total = total_activities_for(trial)
    send_once(trial, :trial_ended_email_sent_at) do
      TrialMailer.ended_email(trial, total).deliver_later
    end
  end

  # A próxima atividade do percurso — a 4ª, para quem fez as 3 do teste. Só
  # para quem praticou: a quem nunca abriu nada, "a próxima" não diz nada.
  def send_next_step(trial)
    return false if trial.trial_next_step_sent_at.present?
    # Quem já recebeu o "último email" (antes de este existir) não recebe mais
    # nada: ele prometeu silêncio.
    return false if trial.trial_winback_sent_at.present?
    return false if trial.trial_ended_email_sent_at.blank?
    return false if trial.trial_ended_email_sent_at > NEXT_STEP_AFTER.ago
    return false if trial.quiz_attempts.none?

    activity = trial.next_path_activity || first_activity_for(trial)
    return false if activity.nil?

    send_once(trial, :trial_next_step_sent_at) do
      TrialMailer.next_step_email(trial, activity).deliver_later
    end
  end

  def send_winback(trial)
    return false if trial.trial_winback_sent_at.present?
    return false if trial.trial_ended_email_sent_at.blank?
    return false if trial.trial_ended_email_sent_at > WINBACK_AFTER.ago

    activity = first_activity_for(trial)
    return false if activity.nil?

    send_once(trial, :trial_winback_sent_at) do
      TrialMailer.winback_email(trial, activity).deliver_later
    end
  end

  # A trava contra email em dobro. Antes cada passo enfileirava e só depois
  # marcava a coluna: uma rodada que caísse entre as duas linhas, ou duas
  # rodadas ao mesmo tempo, mandavam o mesmo email duas vezes.
  #
  # Agora a marcação vem primeiro e é condicional no próprio banco (`WHERE
  # coluna IS NULL`): só uma execução consegue "reservar" a pessoa. E as duas
  # coisas vão na mesma transação — o GoodJob grava o email na fila no mesmo
  # Postgres, então ou a marcação e o email existem juntos, ou nenhum dos dois.
  def send_once(trial, column, **extra)
    User.transaction do
      claimed = User.where(id: trial.id, column => nil)
                    .update_all({ column => Time.current }.merge(extra))
      next false unless claimed == 1

      yield
      true
    end
  end

  # A atividade que vai no email. A escolha mudou de lugar (User) porque a
  # dashboard passou a oferecer a mesma no bloco "Comece por aqui": se cada um
  # escolhesse por conta, o email mandaria para uma e a tela ofereceria outra.
  def first_activity_for(trial)
    trial.suggested_first_activity
  end

  # Quantas atividades a assinatura abriria pra essa pessoa. Número concreto no
  # email do fim do teste: "foi uma porta de entrada, tem 145 do outro lado".
  def total_activities_for(trial)
    return 0 if trial.level.blank?

    Activity.published.where(level: trial.accessible_levels).count
  end
end
