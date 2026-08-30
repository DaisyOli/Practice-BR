class AddTrainingOrganisationToUsers < ActiveRecord::Migration[7.1]
  # A identidade legal de quem EMITE a atestação.
  #
  # A decisão que trouxe estes campos para cá: cada professora é o próprio
  # organismo de formação, e o Practice-BR é ferramenta — como um LMS. Se fosse
  # o contrário (Practice-BR como organismo), nada disto seria coluna: seria uma
  # constante da aplicação, igual para todo mundo.
  #
  # Por isso ficam no `users` e não em config: o SIRET que vai no PDF é o da
  # professora que assina, e duas professoras assinam documentos diferentes.
  #
  # Tudo opcional no banco. Uma professora que nunca vai emitir atestado não
  # deve ser obrigada a preencher SIRET — quem cobra é a atestação, que se
  # recusa a sair completa sem eles.
  def change
    change_table :users, bulk: true do |t|
      t.string :org_name        # raison sociale do organismo
      t.string :org_siret       # 14 dígitos, com checksum de Luhn
      t.string :org_nda         # numéro de déclaration d'activité (o "NDA")
      t.text   :org_address     # endereço que vai impresso no documento
      t.string :org_signatory   # nome e qualidade de quem assina
      t.string :training_title  # intitulé da ação de formação
    end
  end
end
