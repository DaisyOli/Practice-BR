require 'rails_helper'

# É o único email que anuncia perda de dado. Ele tem que renderizar nos três
# idiomas e tem que dizer as três coisas: quando, como impedir, como exportar.
RSpec.describe RetentionMailer, type: :mailer do
  %w[fr en pt].each do |lang|
    context "em #{lang}" do
      let(:user) { create(:user, :student, language: lang, created_at: (3.years + 1.day).ago) }
      let(:mail) { described_class.deletion_warning(user) }

      it 'renderiza e vai para a pessoa certa' do
        expect(mail.to).to eq([user.email])
        expect(mail.subject).to be_present
        expect(mail.body.encoded).to be_present
      end

      it 'traz a data limite no assunto' do
        deadline = user.retention_deadline
        esperado = lang == 'en' ? deadline.strftime('%B %-d, %Y') : deadline.strftime('%d/%m/%Y')

        expect(mail.subject).to include(esperado)
      end

      it 'oferece a exportação antes de apagar' do
        expect(mail.body.encoded).to include('/meus-dados')
      end
    end
  end

  it 'cai no francês quando o idioma não tem versão' do
    user = create(:user, :student, created_at: (3.years + 1.day).ago)
    user.update_column(:language, 'es')

    expect(described_class.deletion_warning(user.reload).subject).to include('sera supprimé')
  end
end
