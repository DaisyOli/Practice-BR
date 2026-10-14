require 'rails_helper'

# O email de boas-vindas serve a dois casos com uma frase só: quem já está
# dentro do app (veio pelo link da landing) e quem fechou a aba antes de
# começar. O botão leva à primeira atividade, já logado, de qualquer aparelho —
# antes ele levava a "Criar nova senha".
RSpec.describe TrialMailer, type: :mailer do
  describe "#welcome_email" do
    let!(:atividade) { create(:activity, :B1, draft: false, title: "Na padaria") }

    def email_for(language)
      user = create(:user, :trial, language: language)
      described_class.welcome_email(user)
    end

    {
      "fr" => ["Bienvenue sur Practice-BR", "Commencer mon premier exercice"],
      "en" => ["Welcome to Practice-BR", "Start my first exercise"],
      "pt" => ["Boas-vindas à Practice-BR", "Começar meu primeiro exercício"]
    }.each do |lang, (subject_fragment, cta)|
      it "sai em #{lang}, com o convite para a primeira atividade" do
        mail = email_for(lang)

        expect(mail.subject).to include(subject_fragment)
        expect(CGI.unescapeHTML(mail.body.encoded)).to include(cta)
      end
    end

    it "cai no francês quando o idioma não tem versão" do
      user = create(:user, :trial)
      user.update_column(:language, "es")

      expect(described_class.welcome_email(user.reload).subject).to include("Bienvenue")
    end

    it "diz o nível, as 3 atividades e até quando o teste vale" do
      user = create(:user, :trial, language: "pt", level: "B1", trial_expires_at: Time.zone.parse("2026-10-21 10:00"))
      body = CGI.unescapeHTML(described_class.welcome_email(user).body.encoded)

      expect(body).to include("B1")
      expect(body).to include("3 atividades")
      expect(body).to include("21/10/2026")
    end

    it "o botão entra sem senha, direto na primeira atividade" do
      user = create(:user, :trial, language: "pt")
      body = described_class.welcome_email(user).body.encoded
      token = body[%r{/entrar\?token=([^"&]+)}, 1]

      expect(token).to be_present
      result = TrialEmailLink.redeem(CGI.unescape(token))
      expect(result.user).to eq(user)
      expect(result.destination).to eq("activity")
      expect(result.activity_id).to eq(atividade.id)
    end

    it "não manda mais para a tela de criar senha" do
      body = email_for("pt").body.encoded

      expect(body).not_to include("reset_password_token")
    end

    it "não fala em procurar professora — o caminho depois do teste é assinar" do
      body = CGI.unescapeHTML(email_for("pt").body.encoded)

      expect(body).not_to include("fale com um professor")
      expect(body).to include("assinar")
    end
  end
end
