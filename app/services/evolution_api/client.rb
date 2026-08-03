# app/services/evolution_api/client.rb
#
# "module EvolutionApi" + el archivo en la carpeta evolution_api/ es la forma
# que tiene Ruby de organizar clases en "namespaces" (como carpetas de
# paquetes en otros lenguajes). Rails, por convención, espera que la clase
# EvolutionApi::Client viva exactamente en app/services/evolution_api/client.rb
# — si el archivo no está en esa ruta exacta, Rails no la va a encontrar sola.

module EvolutionApi
  class Client
    # "attr_reader" genera automáticamente métodos de lectura (getters) para
    # esas variables — evita escribir "def base_url; @base_url; end" a mano.
    attr_reader :base_url, :api_key

    def initialize
      # ENV.fetch busca una variable de entorno. El segundo argumento (si lo
      # hay) es un valor por defecto; sin él, tira error si falta la variable
      # — preferible a que falle silenciosamente más adelante con datos vacíos.
      @base_url = ENV.fetch('EVOLUTION_API_URL')
      @api_key = ENV.fetch('EVOLUTION_API_KEY')
    end

    # Crea la instancia Y devuelve el QR en un solo paso (combina los dos
    # curls que veníamos usando a mano).
    def create_instance_with_qr(instance_name)
      post("/instance/create", {
        instanceName: instance_name,
        qrcode: true,
        integration: "WHATSAPP-BAILEYS"
      })

      get("/instance/connect/#{instance_name}")
    end

    # Pide el QR de nuevo sin recrear la instancia — usado para refrescarlo
    # cuando el anterior venció (WhatsApp los vence cada 20-30 segundos).
    def refresh_qr(instance_name)
      get("/instance/connect/#{instance_name}")
    end

    def connection_state(instance_name)
      get("/instance/connectionState/#{instance_name}")
    end

    def link_to_chatwoot(instance_name:, account_id:, token:, chatwoot_url:, inbox_name:)
      post("/chatwoot/set/#{instance_name}", {
        enabled: true,
        accountId: account_id.to_s,
        token: token,
        url: chatwoot_url,
        signMsg: true,
        reopenConversation: true,
        conversationPending: false,
        nameInbox: inbox_name,
        autoCreate: true,
        importContacts: true,
        importMessages: false
      })
    end

    private

    # Los dos métodos de abajo son "privados" (private): solo se pueden
    # llamar desde adentro de esta misma clase, no desde afuera. Es una forma
    # de decir "esto es un detalle de implementación, no lo uses directo".

    def get(path)
      request(Net::HTTP::Get, path)
    end

    def post(path, body)
      request(Net::HTTP::Post, path, body)
    end

    def request(http_method_class, path, body = nil)
      uri = URI("#{base_url}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"

      req = http_method_class.new(uri)
      req["apikey"] = api_key
      req["Content-Type"] = "application/json"
      req.body = body.to_json if body

      response = http.request(req)

      # JSON.parse convierte el texto que devuelve Evolution API en un Hash
      # de Ruby (como un objeto/diccionario). symbolize_names: true hace que
      # las claves sean símbolos (:state) en vez de strings ("state") —
      # cuestión de gusto/consistencia con el resto del código Ruby.
      JSON.parse(response.body, symbolize_names: true)
    rescue JSON::ParserError
      { error: "Respuesta inválida de Evolution API", raw: response&.body }
    end
  end
end