module Api
  module V1
    class TrialsController < BaseController
      def create
        email = params[:email].to_s.strip.downcase
        level = params[:level].to_s.strip.upcase

        return render_error(:unprocessable_entity, "Email é obrigatório.") if email.blank?
        return render_error(:unprocessable_entity, "Nível é obrigatório.") if level.blank?
        return render_error(:unprocessable_entity, "Nível inválido. Use: A1, A2, B1, B2 ou C1.") unless User::CEFR_LEVELS.include?(level)
        return render_error(:unprocessable_entity, "Este email já tem uma conta. Acesse a plataforma normalmente.") if User.exists?(email: email)

        admin = User.find_by(email: ENV["PLATFORM_ADMIN_EMAIL"])

        user = User.new(
          email: email,
          level: level,
          role: "trial",
          language: requested_language,
          password: SecureRandom.hex(12),
          trial_activities_used: 0,
          trial_expires_at: 7.days.from_now,
          invited_by_id: admin&.id
        )

        unless user.save
          return render_error(:unprocessable_entity, user.errors.full_messages.first)
        end

        raw_token, hashed_token = Devise.token_generator.generate(User, :reset_password_token)
        user.update_columns(
          reset_password_token: hashed_token,
          reset_password_sent_at: Time.current
        )

        TrialMailer.welcome_email(user, raw_token).deliver_later
        TrialMailer.notification_email(user).deliver_later

        # `start_url` é a mudança que importa: a landing redireciona pra ele em
        # vez de mostrar "confira seu email", e a pessoa cai dentro do app já
        # logada. O email segue saindo acima — ele agora é o caminho de volta,
        # não o portão de entrada.
        render json: { ok: true, start_url: start_url_for(user) }, status: :created
      end

      private

      # A landing sabe o idioma da pessoa — ela está navegando em /fr, /en ou
      # /pt — e passa junto. Sem isso toda conta nascia em português, inclusive
      # a de visitante francês, e o email de boas-vindas saía no idioma errado.
      #
      # Não dá pra usar o Accept-Language aqui: quem chama esta API é o servidor
      # da Vercel, não o navegador da pessoa. O cabeçalho seria o de um robô.
      def requested_language
        lang = params[:language].to_s.strip.downcase[0, 2]
        User::LANGUAGES.include?(lang) ? lang : User::DEFAULT_LANGUAGE
      end

      def start_url_for(user)
        trial_start_url(
          token: TrialStartToken.generate(user),
          host:  Rails.application.config.action_mailer.default_url_options[:host],
          protocol: "https"
        )
      end
    end
  end
end
