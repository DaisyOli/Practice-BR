require 'rails_helper'

RSpec.describe User, "organismo de formação", type: :model do
  let(:teacher) { create(:user, :teacher) }

  # O SIRET real do Practice-BR, que já vive na política de privacidade. Serve
  # aqui como caso verdadeiro: se o checksum estiver errado, ele reprova um
  # número que existe.
  let(:siret_valido) { "85194793700013" }

  describe "SIRET" do
    it "aceita um SIRET verdadeiro" do
      teacher.org_siret = siret_valido
      expect(teacher).to be_valid
    end

    it "aceita com espaços, e guarda sem" do
      teacher.update!(org_siret: "851 947 937 00013")
      expect(teacher.reload.org_siret).to eq(siret_valido)
    end

    it "recusa quando não tem 14 dígitos" do
      teacher.org_siret = "8519479370001"
      expect(teacher).not_to be_valid
      expect(teacher.errors[:org_siret].join).to include("14 dígitos")
    end

    # O erro que o checksum existe para pegar: não é o campo vazio (esse a
    # professora vê), é o dígito trocado que atravessa a tela e o PDF.
    it "recusa um dígito trocado, que tem o formato certo" do
      teacher.org_siret = "85194793700014"
      expect(teacher).not_to be_valid
      expect(teacher.errors[:org_siret].join).to include("verificação")
    end

    it "recusa dois dígitos invertidos entre si" do
      teacher.org_siret = "85194793700031"
      expect(teacher).not_to be_valid
    end

    it "não reclama de campo vazio — preencher é opcional" do
      teacher.org_siret = nil
      expect(teacher).to be_valid
    end

    it "formata para leitura no documento" do
      teacher.org_siret = siret_valido
      expect(teacher.formatted_siret).to eq("851 947 937 00013")
    end
  end

  describe "completude" do
    it "uma professora recém-criada não está completa" do
      expect(teacher).not_to be_organisme_complete
      expect(teacher).not_to be_organisme_started
    end

    it "diz o que falta, em português" do
      teacher.update!(org_name: "Mon OF", org_siret: siret_valido)

      expect(teacher).to be_organisme_started
      expect(teacher).not_to be_organisme_complete
      expect(teacher.missing_organisme_fields)
        .to contain_exactly("número de declaração de atividade", "endereço",
                            "nome de quem assina", "intitulé da formação")
    end

    it "fica completa quando os seis campos estão preenchidos" do
      teacher.update!(
        org_name: "Mon OF", org_siret: siret_valido, org_nda: "11 75 12345 75",
        org_address: "12 rue de la Formation, 75011 Paris",
        org_signatory: "Marie Dupont, gérante",
        training_title: "Portugais brésilien — formation à distance"
      )

      expect(teacher).to be_organisme_complete
      expect(teacher.missing_organisme_fields).to be_empty
    end

    # Um campo só com espaços não preenche nada, mas `present?` já sabe disso —
    # o teste trava a regra caso alguém troque por `nil?` algum dia.
    it "espaço em branco não conta como preenchido" do
      teacher.update!(org_name: "   ")
      expect(teacher).not_to be_organisme_started
    end
  end
end
