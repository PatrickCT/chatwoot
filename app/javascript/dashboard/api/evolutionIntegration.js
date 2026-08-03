/* global axios */
// app/javascript/dashboard/api/evolutionIntegration.js
//
// A diferencia de LabelsAPI (que usa los métodos genéricos get/create/show
// de ApiClient porque labels es un CRUD normal), acá nuestras 3 acciones no
// son un CRUD — son comandos puntuales. Por eso definimos 3 métodos propios
// en vez de usar los heredados, pero seguimos reusando "this.url" (que ya
// arma la base con el accountId correcto) para no repetir esa lógica.

import ApiClient from './ApiClient';

class EvolutionIntegrationAPI extends ApiClient {
    constructor() {
        super('evolution_integration', { accountScoped: true });
    }

    createInstance(instanceName) {
        return axios.post(`${this.url}/create_instance`, {
            instance_name: instanceName,
        });
    }

    connectionState(instanceName) {
        return axios.get(`${this.url}/connection_state`, {
            params: { instance_name: instanceName },
        });
    }

    refreshQr(instanceName) {
        return axios.get(`${this.url}/refresh_qr`, {
            params: { instance_name: instanceName },
        });
    }

    linkToChatwoot(instanceName, inboxName) {
        return axios.post(`${this.url}/link_to_chatwoot`, {
            instance_name: instanceName,
            inbox_name: inboxName,
        });
    }
}

export default new EvolutionIntegrationAPI();