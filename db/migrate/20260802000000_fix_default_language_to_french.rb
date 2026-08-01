class FixDefaultLanguageToFrench < ActiveRecord::Migration[7.1]
  # A plataforma tinha DOIS padrões de idioma que discordavam, e o silencioso
  # ganhava:
  #
  #   User::DEFAULT_LANGUAGE = 'pt'   ← o que o código dizia
  #   coluna language default: 'en'   ← o que o banco fazia
  #
  # Como a coluna nunca fica nula, o `set_default_language` do model jamais
  # rodava: era código morto. Toda conta criada até 31/07/2026 nasceu em inglês
  # sem ninguém escolher — inclusive as duas professoras reais e os alunos
  # pagantes, todos francófonos. Emails em inglês pra francês.
  #
  # O padrão passa a ser francês porque é o que o resto do app já fazia: o
  # TrialStartsController, a tela de fim de teste, o BillingController e todos os
  # mailers caem em francês quando não sabem o idioma. Agora o banco concorda
  # com eles.
  def up
    change_column_default :users, :language, from: "en", to: "fr"

    # Correção pontual autorizada pela Daisy em 2026-08-01: as contas de teste
    # que nasceram antes de a landing passar o idioma. Nenhuma delas escolheu
    # inglês — não havia o que escolher. Vieram do site em francês.
    execute <<~SQL
      UPDATE users
      SET language = 'fr'
      WHERE role = 'trial' AND language = 'en'
    SQL
  end

  def down
    change_column_default :users, :language, from: "fr", to: "en"
  end
end
