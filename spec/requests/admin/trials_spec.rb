require 'rails_helper'

RSpec.describe "Admin::Trials", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:user, :admin) }
  let(:trial) { create(:user, :trial, trial_activities_used: 1) }

  describe "POST /admin/trials/:id/send_reminder" do
    context "como admin" do
      it "envia o lembrete e marca trial_reminder_sent_at" do
        sign_in admin

        expect {
          post admin_send_trial_reminder_path(trial)
        }.to have_enqueued_mail(TrialMailer, :reminder_email)

        expect(trial.reload.trial_reminder_sent_at).to be_present
        expect(response).to redirect_to(admin_root_path)
      end
    end

    # O texto é "Você começou — e ainda tem atividades". Em 19/10/2026 o botão
    # mandou isso a contas com zero atividades ("Você fez 0 das 3").
    context "quando o lembrete não faz sentido" do
      before { sign_in admin }

      it "recusa quem não fez nenhuma atividade" do
        zero = create(:user, :trial, trial_activities_used: 0)

        expect { post admin_send_trial_reminder_path(zero) }
          .not_to have_enqueued_mail(TrialMailer, :reminder_email)
        expect(flash[:alert]).to include("só para quem começou")
        expect(zero.reload.trial_reminder_sent_at).to be_nil
      end

      it "recusa quem já terminou o teste" do
        encerrada = create(:user, :trial, trial_activities_used: 1, trial_expires_at: 1.day.ago)

        expect { post admin_send_trial_reminder_path(encerrada) }
          .not_to have_enqueued_mail(TrialMailer, :reminder_email)
      end

      it "só mostra o botão para quem pode receber" do
        trial
        zero = create(:user, :trial, trial_activities_used: 0)

        get admin_root_path

        expect(response.body).to include(admin_send_trial_reminder_path(trial))
        expect(response.body).not_to include(admin_send_trial_reminder_path(zero))
      end
    end

    context "sem ser admin" do
      it "não envia e redireciona" do
        teacher = create(:user, :teacher)
        sign_in teacher

        expect {
          post admin_send_trial_reminder_path(trial)
        }.not_to have_enqueued_mail(TrialMailer, :reminder_email)

        expect(response).to redirect_to(root_path)
      end
    end
  end
end
