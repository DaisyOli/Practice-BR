require 'rails_helper'

# O email de boas-vindas mudou de papel: a pessoa já está dentro do app quando
# ele chega, então ele é o caminho de volta, não o portão. Os testes prendem as
# duas coisas — que ele fala a língua certa e que não manda mais alguém "entrar"
# num lugar onde já está.
RSpec.describe TrialMailer, type: :mailer do
  describe "#welcome_email" do
    def email_for(language)
      user = create(:user, :trial, language: language)
      described_class.welcome_email(user, "token-de-teste")
    end

    {
      "fr" => ["Votre lien pour revenir", "Gardez ce lien"],
      "en" => ["Your link back", "Keep this link"],
      "pt" => ["Seu link para voltar", "Guarde este link"]
    }.each do |lang, (subject_fragment, body_fragment)|
      it "sai em #{lang}" do
        mail = email_for(lang)

        expect(mail.subject).to include(subject_fragment)
        expect(CGI.unescapeHTML(mail.body.encoded)).to include(body_fragment)
      end
    end

    it "cai no francês quando o idioma não tem versão" do
      user = create(:user, :trial)
      user.update_column(:language, "es")

      expect(described_class.welcome_email(user.reload, "t").subject).to include("Votre lien")
    end

    it "leva o link de volta e o nível da pessoa" do
      user = create(:user, :trial, language: "pt", level: "B1")
      body = described_class.welcome_email(user, "token-de-teste").body.encoded

      expect(body).to include("token-de-teste")
      expect(body).to include("B1")
    end

    it "não fala mais em procurar professora — o caminho agora é assinar" do
      body = CGI.unescapeHTML(email_for("pt").body.encoded)

      expect(body).not_to include("fale com um professor")
      expect(body).to include("assinar")
    end
  end
end
