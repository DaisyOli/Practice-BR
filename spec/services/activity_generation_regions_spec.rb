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

    # A primeira versão destas âncoras listava marcas dialetais e o modelo tratou
    # como checklist: uma teleconsulta com "bah", "tu tá", "capaz", "tri",
    # bergamota e chimarrão em quinze linhas. Lista de vocabulário É um checklist —
    # a correção foi tirar o vocabulário, não pedir moderação.
    it "não contêm marca dialetal nenhuma" do
      ancoras = described_class::REGIOES.values.join(" ").downcase

      # Fronteira de palavra, e não `include`: "tri" casa dentro de "indústria" e
      # "capaz" dentro de "capazes". Sem \b o teste acusa dialeto onde não tem.
      %w[bah tri capaz oxe vixe uai égua arretado macaxeira bergamota chimarrão].each do |marca|
        expect(ancoras).not_to match(/\b#{Regexp.escape(marca)}\b/),
                               "a âncora voltou a ensinar dialeto: #{marca}"
      end
    end

    it "ancoram no que acontece ali, não em vocabulário" do
      ancoras = described_class::REGIOES.values.join(" ")

      # Clima, trabalho, deslocamento, rotina — o que muda de verdade entre regiões
      # e dá assunto sem precisar de sotaque escrito.
      expect(ancoras).to match(/rio como estrada/)
      expect(ancoras).to match(/feira livre como centro da semana/)
      expect(ancoras).to match(/agronegócio/)
      expect(ancoras).to match(/inverno que exige casaco/)
    end
  end

  describe "o prompt de sistema" do
    let(:sistema) { described_class::SYSTEM_PROMPT }

    it "rebaixa trabalho de padrão para um contexto entre vários" do
      expect(sistema).to include("UM contexto entre vários, não o padrão")
    end

    it "proíbe cartão-postal com um teste que o modelo pode aplicar sozinho" do
      expect(sistema).to include("FOLHETO")
      expect(sistema).to include("propaganda de agência de viagem")
    end

    # O erro de 03/08/2026: um aluno de PLE IMITA o que lê, então pôr "tu vai" na
    # boca de uma médica ensina uma forma que soa errada na maior parte do Brasil.
    # Variação regional é objeto de compreensão, nunca registro do texto.
    it "manda escrever em português padrão, e proíbe as marcas nominalmente" do
      expect(sistema).to include("A LÍNGUA É PADRÃO. SEM EXCEÇÃO.")
      expect(sistema).to include('"tu" com verbo na 3ª pessoa')
      expect(sistema).to include("nunca de imitação")
    end

    it "tem o teste da caricatura, além do teste do folheto" do
      # Folheto pega paisagem; caricatura pega personagem fantasiado de si mesmo,
      # que foi o defeito de verdade da teleconsulta gaúcha.
      expect(sistema).to include("CARICATURA")
      expect(sistema).to include("fantasiado de si mesmo")
    end

    it "diz que uma menção basta, para não virar concurso de cor local" do
      expect(sistema).to include("Uma menção regional bem colocada vale mais que cinco")
    end

    it "pede contraste cultural, não descrição — os alunos são estrangeiros" do
      expect(sistema).to include("CONTRASTE")
      expect(sistema).to include("Uma atividade que compara vale mais que uma que descreve")
    end

    # O exemplo do schema é o molde mais concreto que o modelo tem do que é "uma
    # história aqui" — e por isso ele imita o que estiver ali. Já errou duas vezes:
    # era um dia de escritório (ensinou trabalho) e virou uma feira de Caruaru com
    # macaxeira, queijo coalho, caldo de cana e forró em quatro frases (ensinou
    # desfile de cor local). Agora ensina só a ESTRUTURA, que é a função dele.
    it "usa um exemplo neutro, que não ensina nem escritório nem cor local" do
      expect(sistema).not_to include("Ana chegou ao trabalho")
      expect(sistema).not_to include("Caruaru")

      exemplo = sistema[/"Dona Lurdes.*?preparar o almoço\."/m]
      expect(exemplo).to be_present
      %w[macaxeira coalho forró chimarrão].each { |marca| expect(exemplo).not_to include(marca) }
      expect(exemplo).not_to include(" pra ")  # contração informal no modelo de escrita
    end
  end
end
