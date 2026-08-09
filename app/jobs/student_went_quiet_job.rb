# Avisa a Daisy quando um aluno PAGANTE para de aparecer.
#
# Existe por causa de um caso real: a primeira aluna orgânica assinou em 20/07,
# praticou até 26/07 e parou. A Daisy só descobriu em 05/08, por acaso, olhando
# o banco por outro motivo — dez dias depois. O aluno já recebia o cutucão
# automático do InactivityNudgeJob; o que não existia era a professora saber.
#
# Não é o mesmo que o InactivityNudgeJob: aquele fala com o aluno em 48h, este
# fala com a Daisy em 7 dias. Um é reengajamento automático, o outro é o pedido
# de um olho humano — com poucos alunos, uma mensagem pessoal dela vale mais que
# qualquer email de sistema.
#
# Só pagantes: quem está no teste tem a sequência de trial cuidando disso, e
# misturar os dois faria o aviso perder o sentido de "atenção, receita em risco".
class StudentWentQuietJob < ApplicationJob
  queue_as :default

  SILENCE = 7.days

  def perform
    last_practice = last_practice_by_user_id
    quiet = paying_students.select { |student| quiet?(student, last_practice[student.id]) }
    return if quiet.empty?

    # deliver_now, e não deliver_later: o job já roda em background, e o carimbo
    # abaixo diz "esta ausência já foi avisada". Entregando depois, uma falha no
    # envio deixaria o carimbo gravado e o email nunca chegaria — a ausência
    # ficaria marcada como avisada sem ninguém ter sido avisado. Falhando aqui,
    # o job tenta de novo e o carimbo só é gravado quando o email saiu.
    AdminMailer.students_went_quiet(quiet, last_practice).deliver_now

    # update_all e não save: nenhuma validação a rodar, e uma consulta só.
    User.where(id: quiet.map(&:id)).update_all(quiet_alert_sent_at: Time.current)
  end

  private

  def paying_students
    User.where(role: "student", subscription_status: "active")
  end

  def quiet?(student, last)
    # Nunca praticou: é ativação, não sumiço, e tem outro dono. Avisar aqui
    # transformaria o alerta num lembrete diário que ninguém lê.
    return false if last.nil?
    return false if last > SILENCE.ago

    # Um aviso por ausência. Só volta a avisar depois que a pessoa reaparecer,
    # senão a Daisy recebe o mesmo email todo dia até o aluno voltar.
    student.quiet_alert_sent_at.nil? || student.quiet_alert_sent_at < last
  end

  # A última prática de todos os alunos pagantes em UMA consulta, em vez de
  # duas por aluno. O mesmo resultado decide quem sumiu e monta o email — antes
  # a view refazia a conta, aluno por aluno, na hora de renderizar.
  #
  # `COALESCE(submitted_at, created_at)` é o `submitted_at || created_at` feito
  # pelo Postgres, LINHA A LINHA. Não é a mesma coisa que o que estava aqui,
  # `maximum(:submitted_at) || maximum(:created_at)`: aquela versão só olhava
  # para `created_at` quando o aluno nunca tinha submetido nada na vida, então
  # uma tentativa recente sem `submitted_at` no meio de tentativas antigas
  # passava batida e a pessoa era dada como sumida.
  #
  # Esta versão também faz o job concordar com `User#practice_days`, que já
  # contava assim. Eram duas definições de "última prática" no mesmo app.
  def last_practice_by_user_id
    QuizAttempt.where(user_id: paying_students.select(:id))
               .group(:user_id)
               .maximum(Arel.sql("COALESCE(submitted_at, created_at)"))
  end
end
