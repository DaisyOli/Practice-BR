require 'rails_helper'

# A ambientação regional das atividades geradas.
#
# O problema (03/08/2026): tudo caía em São Paulo e no mundo do trabalho. A causa
# estava no prompt de sistema — "vida profissional" e "cotidiano adulto urbano"
# como contextos recomendados, sem nenhuma dimensão regional, e o exemplo de
# paragraph_ordering sendo um dia de escritório.
#
# A correção tem duas metades, e a segunda é a que importa: explicar no prompt POR
# QUE variar não faz variar. Cada geração é uma chamada independente, sem memória
# das anteriores, então "alterne entre as regiões" é instrução que o modelo não tem
# como cumprir — ele escolhe a mais provável, sempre a mesma. O sorteio no código
# é o que produz variedade de verdade.
RSpec.describe ActivityGenerationService, "ambientação regional" do
  let(:teacher) { create(:user, :teacher) }
  let(:client)  { instance_double(Anthropic::Client) }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("chave-de-teste")
    allow(Anthropic::Client).to receive(:new).and_return(client)
  end

  describe "o sorteio" do
    it "manda uma das cinco regiões junto com o pedido" do
      enviado = described_class.new(prompt: "atividade de pretérito perfeito", teacher: teacher)
                               .send(:prompt_com_regiao)

      expect(enviado).to include("Ambientação sorteada")
      expect(described_class::REGIOES.keys).to include(a_string_including(enviado[/Norte|Nordeste|Centro-Oeste|Sudeste|Sul/]))
    end

    it "preserva o pedido da professora acima da ambientação" do
      enviado = described_class.new(prompt: "quero uma atividade sobre subjuntivo", teacher: teacher)
                               .send(:prompt_com_regiao)

      expect(enviado).to start_with("quero uma atividade sobre subjuntivo")
    end

    it "diz explicitamente que o pedido vence a ambientação sorteada" do
      # Sem isto, um pedido "atividade sobre o metrô de São Paulo" entraria em
      # conflito com um sorteio de "Norte" e o modelo escolheria no escuro.
      enviado = described_class.new(prompt: "x", teacher: teacher).send(:prompt_com_regiao)

      expect(enviado).to include("o pedido manda")
    end

    it "de fato varia entre chamadas — é isso que o prompt sozinho não fazia" do
      servico = described_class.new(prompt: "atividade", teacher: teacher)

      sorteadas = 60.times.map do
        described_class::REGIOES.keys.find { |r| servico.send(:prompt_com_regiao).include?(r) }
      end.uniq

      # Com 5 regiões e 60 sorteios, ver menos de 4 seria sorte absurda ou bug.
      expect(sorteadas.size).to be >= 4
    end
  end

  describe "as cinco regiões" do
    it "cobrem o país inteiro, sem São Paulo como região própria" do
      chaves = described_class::REGIOES.keys.join(" ")

      expect(chaves).to include("Norte", "Nordeste", "Centro-Oeste", "Sudeste", "Sul")
      # São Paulo era o default involuntário; o Sudeste entra explicitamente "fora
      # de São Paulo" pra não recriar o problema por dentro da correção.
      expect(chaves).to include("fora de São Paulo")
    end

    it "ancoram em língua e cotidiano, não em ponto turístico" do
      ancoras = described_class::REGIOES.values.join(" ")

      # Marcadores linguísticos reais — o que faz um aluno entender Recife depois
      # de só ter ouvido paulistano.
      expect(ancoras).to include("égua", "oxe", "uai", "bah")
      expect(ancoras).to include("tu")            # o "tu" gaúcho com verbo na 3ª
      expect(ancoras).to include("macaxeira")     # x mandioca
      expect(ancoras).to include("bergamota")     # x mexerica
    end

    it "traz o açaí salgado do Pará, que contradiz a tigela doce do Sudeste" do
      # É o melhor anti-clichê da lista: surpreende, é verdade, e serve de material
      # intercultural em vez de folheto.
      expect(described_class::REGIOES.keys.grep(/Norte/).first).to be_present
      expect(described_class::REGIOES.values.join).to match(/açaí SALGADO/)
    end
  end

  describe "o prompt de sistema" do
    let(:sistema) { described_class::SYSTEM_PROMPT }

    it "rebaixa trabalho de padrão para um contexto entre vários" do
      expect(sistema).to include("UM contexto entre vários, não o padrão")
    end

    it "proíbe cartão-postal com um teste que o modelo pode aplicar sozinho" do
      expect(sistema).to include("folheto de agência de viagem")
    end

    it "pede contraste cultural, não descrição — os alunos são estrangeiros" do
      expect(sistema).to include("CONTRASTE")
      expect(sistema).to include("Uma atividade que compara vale mais que uma que descreve")
    end

    it "não usa mais o dia de escritório como molde de história" do
      # O exemplo de paragraph_ordering era "Ana chegou ao trabalho às 9h" — o
      # molde mais concreto que o modelo tinha do que é uma história aqui.
      expect(sistema).not_to include("Ana chegou ao trabalho")
      expect(sistema).to include("feira de Caruaru")
    end
  end
end
