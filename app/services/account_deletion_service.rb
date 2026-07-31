# Apagar uma conta é mais do que `user.destroy`: se existe assinatura na Stripe,
# ela precisa ser cancelada, e as duas coisas precisam valer juntas ou nenhuma.
#
# Isto virou serviço porque agora há **dois** caminhos até aqui e eles não podem
# divergir: a pessoa pedindo em `/excluir-conta` e o `AccountRetentionJob`
# apagando conta abandonada. Uma correção feita num lugar e esquecida no outro é
# exatamente o bug que já aconteceu uma vez — conta apagada, assinatura viva,
# cartão sendo cobrado de quem não tem mais como entrar e cancelar.
class AccountDeletionService
  # Professora não se apaga: as atividades dela seguem sendo usadas pelos alunos,
  # ou seja, são conteúdo da plataforma e não dado pessoal dela. Vale também para
  # o caminho automático — uma professora que passou 3 anos sem responder quiz
  # (ela cria atividades, não responde) não pode virar candidata a exclusão.
  class TeacherRefused < StandardError; end

  def initialize(user, notify_admin: true)
    @user         = user
    @notify_admin = notify_admin
  end

  # Devolve o id de quem foi apagado. Levanta Stripe::StripeError ou
  # ActiveRecord::ActiveRecordError se algo falhar — e nesse caso **nada** foi
  # apagado, porque tudo acontece dentro da transação.
  def call
    raise TeacherRefused, "conta de professora não é apagada por este caminho" if @user.teacher?

    user_id     = @user.id
    role        = @user.role
    customer_id = @user.stripe_customer_id

    # Apagar e cancelar dentro da MESMA transação. Assim os dois só valem se os
    # dois derem certo: se o Stripe falhar, o destroy volta atrás; se o destroy
    # falhar (uma associação sem `dependent:` derrubando por chave estrangeira,
    # por exemplo), o Stripe nem chega a ser chamado.
    #
    # Segurar uma transação aberta durante uma chamada de rede não é ideal, mas
    # aqui o volume é ínfimo e a alternativa é pior: cancelar fora dela deixaria
    # a pessoa sem acesso pago e com a conta de pé, ou com assinatura órfã.
    ActiveRecord::Base.transaction do
      @user.destroy!
      cancel_subscription!
    end

    if @notify_admin
      AdminMailer.account_deleted_notification(
        user_id: user_id, role: role, stripe_customer_id: customer_id
      ).deliver_later
    end

    user_id
  end

  private

  # Cancelamento imediato, não `cancel_at_period_end`. A conta está sendo
  # apagada: deixar a assinatura agendada manteria, num plano anual, uma
  # assinatura "ativa" no Stripe por meses pra alguém que não existe mais.
  #
  # Lê os atributos depois do destroy de propósito — o objeto continua em memória
  # com eles, e é a única forma de cancelar dentro da mesma transação.
  def cancel_subscription!
    sub_id = @user.stripe_subscription_id
    return if sub_id.blank?
    return if @user.subscription_status == "canceled"

    Stripe::Subscription.cancel(sub_id)
    Rails.logger.info "[Conta] Assinatura cancelada antes de apagar · user ##{@user.id}"
  end
end
