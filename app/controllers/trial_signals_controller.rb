# Recebe do navegador os sinais de que há uma pessoa do outro lado
# (trial_signal_controller.js). Só contas de teste, só a primeira vez de cada
# sinal, e só uma data: nada do que a pessoa escreveu passa por aqui.
#
# Não passa pelo check_trial_restrictions!: quem está com o teste encerrado ainda
# navega pela dashboard, e o sinal não pode virar um redirecionamento.
class TrialSignalsController < ApplicationController
  skip_before_action :check_trial_restrictions!
  skip_before_action :check_payment_status!

  COLUMNS = {
    "app"      => :first_human_at,
    "activity" => :first_activity_human_at,
    "answer"   => :first_answer_at
  }.freeze

  def create
    column = COLUMNS[params[:kind]]
    if column && current_user.trial?
      # Condicional no próprio banco: duas abas ao mesmo tempo não sobrescrevem
      # a primeira data.
      User.where(id: current_user.id, column => nil).update_all(column => Time.current)
    end

    head :no_content
  end
end
