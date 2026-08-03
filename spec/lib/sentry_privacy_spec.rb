# O relatório de erros não pode virar o vazamento que a faxina de 30 e 31/07
# fechou. Os logs pararam de guardar email de aluno; mandar o mesmo dado pra um
# serviço externo desfaria aquilo em silêncio — e em silêncio é o pior jeito,
# porque ninguém repara.
#
# Estes testes exercitam a MESMA lógica do `before_send` de
# `config/initializers/sentry.rb`. Não dá pra chamar o initializer aqui: ele sai
# na primeira linha quando não há SENTRY_DSN, que é justamente o estado de teste.
# Então a regra é reproduzida, e o que trava é a intenção: se alguém afrouxar a
# limpeza lá, estes testes continuam passando — mas o spec de leitura do arquivo,
# no fim, pega a remoção da salvaguarda.
require 'rails_helper'

RSpec.describe "Privacidade no relatório de erros" do
  let(:email_in_text) { /[\w.+-]+@[\w-]+\.[\w.-]+/ }
  let(:param_filter)  { ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }

  describe "email escrito no texto da exceção" do
    # O caso real: o email está escrito na FRASE, e nenhum filtro de PARÂMETRO
    # alcança uma frase.
    #
    # O exemplo não é `ActiveRecord::RecordNotFound` de propósito: ela nunca chega
    # ao Sentry, porque o sentry-rails já a exclui por padrão. Quem chega é o erro
    # não previsto — a falha de correção, o erro da Resend citando o destinatário.
    it "some do texto de um erro não previsto" do
      mensagem = "falha ao corrigir a resposta de evelagonotte@yahoo.fr"

      limpa = mensagem.gsub(email_in_text, "[email removido]")

      expect(limpa).to eq("falha ao corrigir a resposta de [email removido]")
      expect(limpa).not_to include("evelagonotte")
      expect(limpa).not_to include("yahoo.fr")
    end

    it "pega mais de um email na mesma frase" do
      mensagem = "merge falhou entre a@b.fr e c.d+tag@e-f.com"

      limpa = mensagem.gsub(email_in_text, "[email removido]")

      expect(limpa).to eq("merge falhou entre [email removido] e [email removido]")
    end

    it "não estraga mensagem sem email nenhum" do
      mensagem = "PG::ConnectionBad: could not connect to server"

      expect(mensagem.gsub(email_in_text, "[email removido]")).to eq(mensagem)
    end
  end

  describe "parâmetros da requisição" do
    # A lista vem de filter_parameter_logging.rb, e é de propósito: uma lista só,
    # num lugar só. Quem adicionar um campo sensível lá protege os dois caminhos.
    it "filtra os mesmos campos que os logs já filtravam" do
      params = {
        "email"    => "aluno@exemplo.fr",
        "password" => "segredo123",
        "answers"  => "a resposta aberta inteira do aluno",
        "level"    => "B1"
      }

      filtrados = param_filter.filter(params)

      expect(filtrados["email"]).to    eq("[FILTERED]")
      expect(filtrados["password"]).to eq("[FILTERED]")
      expect(filtrados["answers"]).to  eq("[FILTERED]")
      expect(filtrados["level"]).to    eq("B1")
    end

    it "alcança os answers de cada tipo de exercício, pelo casamento parcial" do
      params = { "sentence_ordering_answers" => "1,3,2", "column_matching_answers" => "a-b" }

      filtrados = param_filter.filter(params)

      expect(filtrados.values).to all(eq("[FILTERED]"))
    end
  end

  # Salvaguardas que não têm como ser exercitadas sem DSN, mas cuja REMOÇÃO
  # precisa quebrar alguma coisa. Sem isto, alguém "limpando" o initializer um dia
  # tira a proteção e nada avisa.
  describe "o initializer mantém as salvaguardas" do
    let(:fonte) { Rails.root.join("config/initializers/sentry.rb").read }

    it "fica inteiramente desligado sem SENTRY_DSN" do
      expect(fonte).to include('return if ENV["SENTRY_DSN"].blank?')
    end

    it "não manda dado pessoal por padrão" do
      expect(fonte).to match(/config\.send_default_pii\s*=\s*false/)
    end

    it "reaproveita os filtros do Rails em vez de manter lista própria" do
      expect(fonte).to include("Rails.application.config.filter_parameters")
    end

    it "limpa o texto das exceções, não só os parâmetros" do
      expect(fonte).to include("config.before_send")
      expect(fonte).to include("[email removido]")
    end

    # Tracing é a parte mais pesada da biblioteca, e o dyno tem 512MB divididos
    # com o GoodJob dentro do Puma.
    #
    # A armadilha: `0.0` LIGA o tracing. É uma taxa válida, então o railtie
    # registra os subscribers e faz patch em ActiveSupport::Notifications pra
    # descartar tudo no fim — paga o preço inteiro e não guarda nada. Por isso
    # o teste não olha o texto do arquivo: pergunta pro próprio Sentry.
    it "não liga performance tracing" do
      expect(fonte).to match(/config\.traces_sample_rate\s*=\s*nil/)
    end

    it "e `nil` é o que desliga de verdade — `0.0` não desligaria" do
      configurada = lambda do |rate|
        config = Sentry::Configuration.new
        config.dsn                  = "https://publica@o0.ingest.de.sentry.io/0"
        config.enabled_environments = %w[production]
        config.environment          = "production"
        config.traces_sample_rate   = rate
        config.tracing_enabled?
      end

      expect(configurada.call(nil)).to be(false)
      expect(configurada.call(0.0)).to be(true)
    end

    # `SystemExit` não está em Sentry::Rails::IGNORE_DEFAULT nem no IGNORE_DEFAULT
    # do sentry-ruby — conferido rodando. Sem esta linha, todo `heroku run` que
    # termina mal vira email.
    it "ignora SystemExit, que não é defeito de aplicação" do
      expect(fonte).to include('config.excluded_exceptions += ["SystemExit"]')
    end

    it "e o padrão do SDK realmente não cobria isso" do
      padrao = Sentry::Configuration.new.excluded_exceptions
      expect(padrao).not_to include("SystemExit")
    end

    it "só reporta em produção" do
      expect(fonte).to match(/config\.enabled_environments\s*=\s*%w\[production\]/)
    end
  end

  # O initializer tem uma característica traiçoeira: em desenvolvimento e em teste
  # ele sai na linha 14 e NUNCA executa o resto. Ou seja, o corpo do arquivo — o
  # único código que roda em produção — não é exercitado por nenhum outro teste.
  # Foi assim que um `ActiveSupport::ParameterFilter` sem `require` passou: subia
  # limpo aqui e derrubaria o app no boot no instante em que SENTRY_DSN existisse.
  #
  # Só um boot de verdade, com DSN, pega esse tipo de erro. Por isso o subprocesso.
  describe "o boot com SENTRY_DSN definido" do
    it "sobe sem levantar exceção" do
      env = { "SENTRY_DSN" => "https://publica@o0.ingest.de.sentry.io/0", "RAILS_ENV" => "test" }
      comando = %(require "#{Rails.root}/config/environment"; print Sentry.initialized?)

      saida = Bundler.with_unbundled_env do
        IO.popen(env, ["ruby", "-e", comando], err: [:child, :out], chdir: Rails.root.to_s, &:read)
      end

      expect($?.exitstatus).to eq(0), "o initializer quebrou no boot:\n#{saida}"
      expect(saida).to end_with("true"), "o Sentry não inicializou mesmo com DSN:\n#{saida}"
    end
  end

  # A regra de ouro nº 5 do docs/PROTECAO_DE_DADOS.md: todo terceiro novo entra em
  # três lugares ANTES de ir pra produção. O item mais fácil de esquecer é o
  # registre — ele não aparece em lugar nenhum do app, então nada quebra quando
  # fica desatualizado. Ele só fica mentindo. Aqui ele quebra.
  describe "o novo subprocessador está declarado nos três lugares" do
    it "na tabela de subprocessadores das três políticas" do
      %w[fr en pt].each do |lang|
        conteudo = Rails.root.join("app/views/home/_privacy_#{lang}.html.erb").read
        expect(conteudo).to include("Sentry"), "faltou o Sentry na política em #{lang}"
      end
    end

    it "no registre des traitements (art. 30)" do
      expect(Rails.root.join("docs/REGISTRE_DES_TRAITEMENTS.md").read).to include("Sentry")
    end

    it "na tabela de DPAs" do
      expect(Rails.root.join("docs/PROTECAO_DE_DADOS.md").read).to include("Sentry")
    end
  end
end
