module Admin
  class TrialsController < BaseController
    def send_reminder
      user = User.trials.find(params[:id])
      unless user.trial_reminder_allowed?
        return redirect_to(admin_root_path, alert: "Este lembrete é só para quem começou e ainda está no teste.")
      end

      TrialMailer.reminder_email(user).deliver_later
      user.update_column(:trial_reminder_sent_at, Time.current)

      redirect_to admin_root_path, notice: "Lembrete enviado para #{user.email}."
    end
  end
end
