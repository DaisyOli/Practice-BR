# Recebe do navegador até onde o aluno chegou no quiz (quiz_visit_controller.js,
# ponto 2.1). Só a posição e duas datas: nada do que a pessoa escreveu passa por
# aqui.
#
# Medição nunca atrapalha nem redireciona: sem as travas do teste e do
# pagamento, e sempre 204, até quando não grava nada.
class ActivityVisitsController < ApplicationController
  skip_before_action :check_trial_restrictions!
  skip_before_action :check_payment_status!

  def create
    activity = Activity.published.find_by(slug: params[:slug])

    if activity && current_user.student_like?
      ActivityVisit.record!(user: current_user, activity: activity, token: params[:token],
                            step: params[:step], answered: params[:answered] == true || params[:answered] == "true")
    end

    head :no_content
  end
end
