require 'rails_helper'

RSpec.describe VideoTimestamp do
  describe ".parse" do
    it "entende os formatos do YouTube" do
      expect(described_class.parse("0:05")).to eq(5)
      expect(described_class.parse("1:20")).to eq(80)
      expect(described_class.parse("12:45")).to eq(765)
      expect(described_class.parse("75:30")).to eq(4530)   # minutos sem hora
      expect(described_class.parse("1:02:15")).to eq(3735)
      expect(described_class.parse(" 1:20 ")).to eq(80)
    end

    it "aceita segundos soltos, como texto ou número" do
      expect(described_class.parse("95")).to eq(95)
      expect(described_class.parse(95)).to eq(95)
    end

    it "vazio é nil (vídeo inteiro); escrito errado é :invalid" do
      expect(described_class.parse("")).to be_nil
      expect(described_class.parse(nil)).to be_nil
      expect(described_class.parse("abc")).to eq(:invalid)
      expect(described_class.parse("1:2")).to eq(:invalid)     # segundos com 1 dígito
      expect(described_class.parse("1:60")).to eq(:invalid)    # segundo 60
      expect(described_class.parse("1:75:00")).to eq(:invalid) # minuto 75 com hora
      expect(described_class.parse("-5")).to eq(:invalid)
    end
  end

  describe ".to_label" do
    it "volta para o formato que a gente lê" do
      expect(described_class.to_label(5)).to eq("0:05")
      expect(described_class.to_label(80)).to eq("1:20")
      expect(described_class.to_label(3735)).to eq("1:02:15")
      expect(described_class.to_label(nil)).to be_nil
    end
  end
end
