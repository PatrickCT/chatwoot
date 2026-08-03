# app/controllers/api/v1/accounts/evolution_integration_controller.rb
#
# "Api::V1::Accounts::EvolutionIntegrationController" — el nombre completo de
# la clase tiene que reflejar la carpeta donde vive el archivo, separando
# cada carpeta con "::". Es la convención de Rails para que sepa qué archivo
# cargar sin que vos tengas que escribir ningún "import" — a diferencia de
# TypeScript, en Ruby/Rails casi nunca importás nada a mano, el framework
# encuentra la clase por su nombre + ubicación.

class Api::V1::Accounts::EvolutionIntegrationController < Api::V1::Accounts::BaseController
  # BaseController ya se encarga de: confirmar que hay un usuario logueado,
  # y dejar disponible Current.account / Current.user en todos los métodos
  # de acá abajo. Por eso no hace falta autenticar nada nosotros mismos.
  #
  # check_admin_authorization? viene de Api::BaseController (el padre de
  # BaseController) y confirma que el usuario logueado sea ADMINISTRADOR de
  # la cuenta, no solo cualquier agente — importante acá porque esta
  # integración deja crear/vincular conexiones de WhatsApp completas.
  before_action :check_admin_authorization?

  def create_instance
    result = client.create_instance_with_qr(instance_name)
    render json: result
  end

  def refresh_qr
    result = client.refresh_qr(instance_name)
    render json: result
  end

  def connection_state
    result = client.connection_state(instance_name)
    render json: result
  end

  def link_to_chatwoot
    result = client.link_to_chatwoot(
      instance_name: instance_name,
      account_id: Current.account.id,
      token: Current.user.access_token.token,
      # No usamos FRONTEND_URL directo: esa es la URL pública para el
      # navegador (ej. "http://localhost:3000" en desarrollo), pero
      # Evolution API corre en OTRO container y necesita una dirección
      # distinta para llegar hasta acá (host.docker.internal en
      # desarrollo, la URL pública real en producción). Por eso usamos
      # una variable separada, con FRONTEND_URL como fallback para no
      # romper producción si alguien no la configura.
      chatwoot_url: ENV.fetch('CHATWOOT_URL_FOR_EVOLUTION', ENV['FRONTEND_URL']),
      inbox_name: params[:inbox_name]
    )
    render json: result
  end

  private

  # "||=" significa "asigná esto SOLO si @client todavía no tiene valor".
  # Es un patrón muy común en Ruby para "memoizar" (calcular una vez y
  # reusar el resultado dentro del mismo request).
  def client
    @client ||= EvolutionApi::Client.new
  end

  # params[:instance_name] lee el parámetro que mandó el frontend, ya sea
  # por query string (?instance_name=...) o por body JSON, Rails lo unifica
  # todo en el mismo objeto "params".
  def instance_name
    params[:instance_name]
  end
end