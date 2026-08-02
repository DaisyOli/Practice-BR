class AddLanguageChosenAtToUsers < ActiveRecord::Migration[7.1]
  # Separa "a pessoa escolheu este idioma" de "este idioma caiu nela".
  #
  # Até agora as duas coisas eram indistinguíveis, e a diferença importa: um
  # `language = 'en'` podia ser o default antigo da coluna (ver as migrações de
  # 20260802000000 e 20260802002000, que consertaram justamente isso) ou uma
  # escolha de verdade. Sem saber qual, qualquer tela que fale a língua da pessoa
  # tem que apostar — e apostar em inglês num público francófono é o erro que
  # gerou esta sequência inteira de correções.
  #
  # Fica nulo pra todo mundo que já existe, e é o correto: ninguém escolheu
  # idioma nenhum antes de hoje, porque o seletor não existia na interface.
  def change
    add_column :users, :language_chosen_at, :datetime
  end
end
