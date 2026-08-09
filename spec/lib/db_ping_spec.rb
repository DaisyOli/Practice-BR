# O ping do banco vinha de fora do repositório — um comando digitado no painel do
# Heroku Scheduler. Agora é `rake db:ping`, e a mudança tem um propósito além de
# arrumação: a integração de Rake do SDK marca a falha com `rake_task: db:ping`,
# separando no Sentry a queda que ninguém viu da queda que aconteceu na cara de
# um aluno.
#
# Só que essa etiqueta não é escrita por nenhuma linha nossa — ela vem de graça de
# uma biblioteca. Todo o valor da mudança está apoiado numa suposição sobre código
# de terceiro, e suposição sobre terceiro é exatamente o tipo de coisa que muda
# num `bundle update` sem ninguém perceber. É isso que este arquivo trava.
require 'rails_helper'
require 'rake'

RSpec.describe "db:ping" do
  before(:all) do
    # O `:environment` de verdade já rodou: o rails_helper carregou o app. Aqui
    # ele só precisa existir como nome, para a tarefa poder depender dele.
    Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)

    unless Rake::Task.task_defined?("db:ping")
      Rake.application.rake_require("tasks/db_ping", [Rails.root.join("lib").to_s])
    end
  end

  subject(:tarefa) { Rake::Task["db:ping"] }

  # Rake roda cada tarefa uma vez por processo. Sem isto, o segundo exemplo
  # passaria sem executar nada — e passaria para sempre.
  after { tarefa.reenable }

  it "toca o banco de verdade" do
    expect { tarefa.invoke }.to output(/\[db:ping\] ok/).to_stdout
  end

  # A tarefa não tem `rescue`, e é de propósito: quem transforma a exceção em
  # evento do Sentry é a integração de Rake, e ela só é acionada se o erro subir
  # até o Rake. Um `rescue` bem-intencionado aqui apagaria o alerta inteiro.
  it "deixa a falha de conexão subir em vez de engolir" do
    allow(ActiveRecord::Base).to receive(:connection)
      .and_raise(ActiveRecord::DatabaseConnectionError, "sem conexão")

    expect { tarefa.invoke }.to raise_error(ActiveRecord::DatabaseConnectionError)
  end

  describe "a etiqueta vem do SDK, e o SDK precisa continuar colocando" do
    it "a integração de Rake não está desligada por configuração" do
      expect(Sentry::Configuration.new.skip_rake_integration).to be(false)
    end

    # O flag acima só diz que ninguém desligou. Quem de fato põe a etiqueta é um
    # `prepend` em Rake::Application — se a gem parar de aplicá-lo, o flag
    # continuaria false e a etiqueta sumiria em silêncio.
    it "e o patch que põe a etiqueta está aplicado em Rake::Application" do
      expect(Rake::Application.ancestors).to include(Sentry::Rake::Application)
    end

    it "e é `rake_task` com o nome da tarefa que ele marca" do
      fonte = Sentry::Rake::Application.instance_method(:display_error_message).source_location.first

      expect(File.read(fonte)).to include('scope.set_tag("rake_task", task_name)')
    end
  end
end
