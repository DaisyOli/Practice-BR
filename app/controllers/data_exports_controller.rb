# Direito de acesso e de portabilidade (RGPD arts. 15 e 20 · LGPD art. 18).
#
# São duas telas porque são dois direitos: `new` mostra de forma inteligível o
# que guardamos (acesso), e `download` entrega o arquivo em formato de leitura
# automática (portabilidade). Um JSON solto atenderia a lei e seria péssimo de
# ler; uma página sem download não seria portável.
class DataExportsController < ApplicationController
  def new
    @export = DataExportService.new(current_user).call
  end

  def download
    service = DataExportService.new(current_user)

    Rails.logger.info "[Dados] Exportação gerada · user ##{current_user.id}"

    send_data JSON.pretty_generate(service.call),
              filename: service.filename,
              type: "application/json",
              disposition: "attachment"
  end
end
