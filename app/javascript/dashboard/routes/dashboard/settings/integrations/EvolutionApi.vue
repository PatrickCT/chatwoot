<script>
// Options API (el mismo estilo que Webhooks/Index.vue): un objeto con
// "data" (estado), "methods" (funciones), en vez del estilo <script setup>
// que vas a ver en componentes más nuevos del proyecto. Seguimos este
// porque es el que usa el archivo de referencia que miramos.

import { useAlert } from 'dashboard/composables';
import EvolutionIntegrationAPI from 'dashboard/api/evolutionIntegration';
import NextButton from 'dashboard/components-next/button/Button.vue';
import SettingsLayout from '../SettingsLayout.vue';

export default {
  components: {
    SettingsLayout,
    NextButton,
  },
  data() {
    return {
      instanceName: '',
      inboxName: '',
      qrCodeBase64: null,
      connectionStatus: null,
      isCreating: false,
      isCheckingStatus: false,
      isLinking: false,
      // Referencias a los setInterval, para poder cancelarlos después
      // (con clearInterval) — si no los guardás en algún lado, no hay
      // forma de pararlos más adelante.
      qrRefreshTimer: null,
      statusCheckTimer: null,
    };
  },
  computed: {
    isConnected() {
      return this.connectionStatus === 'open';
    },
    canLinkToChatwoot() {
      return this.isConnected && this.inboxName.trim().length > 0;
    },
  },
  // "beforeUnmount" corre justo antes de que Vue destruya este componente
  // (por ejemplo, si el usuario navega a otra pantalla). Es el lugar
  // correcto para cancelar cualquier setInterval — si no lo hacés, el
  // timer sigue corriendo en segundo plano para siempre, aunque la
  // pantalla ya no exista (una fuga de memoria clásica).
  beforeUnmount() {
    this.clearTimers();
  },
  methods: {
    clearTimers() {
      if (this.qrRefreshTimer) clearInterval(this.qrRefreshTimer);
      if (this.statusCheckTimer) clearInterval(this.statusCheckTimer);
      this.qrRefreshTimer = null;
      this.statusCheckTimer = null;
    },

    startPolling() {
      // El QR de WhatsApp vence cada 20-30 segundos — lo refrescamos cada
      // 25 para estar seguros de que siempre haya uno vigente en pantalla.
      this.qrRefreshTimer = setInterval(() => {
        this.refreshQrCode();
      }, 25000);

      // Consultamos el estado de conexión más seguido (cada 5 segundos)
      // para detectar automáticamente cuando el usuario escanea, sin que
      // tenga que tocar el botón "Verificar conexión" a mano.
      this.statusCheckTimer = setInterval(() => {
        this.checkConnection({ silent: true });
      }, 5000);
    },

    async refreshQrCode() {
      try {
        const response = await EvolutionIntegrationAPI.refreshQr(
          this.instanceName
        );
        this.qrCodeBase64 = response.data.base64;
      } catch (error) {
        // Si falla un refresco puntual no interrumpimos nada — el próximo
        // intento (25 segundos después) puede funcionar bien igual.
      }
    },

    async createInstance() {
      if (!this.instanceName.trim()) {
        useAlert('Escribí un nombre de instancia primero.');
        return;
      }

      this.isCreating = true;
      this.qrCodeBase64 = null;
      this.connectionStatus = null;

      try {
        const response = await EvolutionIntegrationAPI.createInstance(
          this.instanceName
        );
        // La respuesta de Evolution API trae el campo "base64" con la
        // imagen del QR ya lista para usar como src de un <img>.
        this.qrCodeBase64 = response.data.base64;
        this.startPolling();
      } catch (error) {
        useAlert('No se pudo crear la instancia. Revisá el nombre e intentá de nuevo.');
      } finally {
        this.isCreating = false;
      }
    },

    async checkConnection({ silent = false } = {}) {
      if (!this.instanceName.trim()) return;

      const wasConnectedBefore = this.isConnected;
      if (!silent) this.isCheckingStatus = true;

      try {
        const response = await EvolutionIntegrationAPI.connectionState(
          this.instanceName
        );
        // Evolution API devuelve: { "instance": { "state": "open" | "connecting" | ... } }
        this.connectionStatus = response.data?.instance?.state || 'unknown';

        // Si justo ahora pasó a "conectado" (antes no lo estaba), avisamos
        // y frenamos el polling — ya no hace falta seguir refrescando el
        // QR ni chequeando el estado cada 5 segundos.
        if (this.isConnected && !wasConnectedBefore) {
          useAlert('¡Conectado! Ya podés vincularlo a Chatwoot.');
          this.clearTimers();
        }
      } catch (error) {
        if (!silent) {
          useAlert('No se pudo consultar el estado de la conexión.');
        }
      } finally {
        if (!silent) this.isCheckingStatus = false;
      }
    },

    async linkToChatwoot() {
      this.isLinking = true;

      try {
        await EvolutionIntegrationAPI.linkToChatwoot(
          this.instanceName,
          this.inboxName
        );
        useAlert('¡Listo! Revisá Configuración → Bandejas de entrada.');
      } catch (error) {
        useAlert('No se pudo conectar con Chatwoot. Revisá los datos e intentá de nuevo.');
      } finally {
        this.isLinking = false;
      }
    },
  },
};
</script>

<template>
  <SettingsLayout :is-loading="false" :no-records-found="false">
    <template #header>
      <div class="p-4">
        <h1 class="text-xl font-semibold">Conectar WhatsApp (Evolution API)</h1>
        <p class="text-n-slate-11">
          Creá una instancia nueva, escaneá el QR, y vinculala a un inbox de
          Chatwoot — sin usar la terminal.
        </p>
      </div>
    </template>

    <template #body>
      <div class="p-4 max-w-lg flex flex-col gap-6">
        <!-- Paso 1: crear instancia -->
        <div class="flex flex-col gap-2">
          <label for="instance-name">Nombre de la instancia</label>
          <input
            id="instance-name"
            v-model="instanceName"
            type="text"
            placeholder="ej: cobranza"
            :disabled="isCreating || !!qrCodeBase64"
          />
          <NextButton
            v-if="!qrCodeBase64"
            blue
            label="Crear y generar QR"
            :is-loading="isCreating"
            @click="createInstance"
          />
        </div>

        <!-- Paso 2: escanear -->
        <div v-if="qrCodeBase64" class="flex flex-col gap-2 items-start">
          <p>Escaneá este código desde WhatsApp → Dispositivos vinculados:</p>
          <img :src="qrCodeBase64" alt="Código QR de WhatsApp" class="w-64 h-64" />
          <NextButton
            slate
            faded
            label="Verificar conexión"
            :is-loading="isCheckingStatus"
            @click="checkConnection"
          />
          <p v-if="connectionStatus">
            Estado: <strong>{{ connectionStatus }}</strong>
          </p>
        </div>

        <!-- Paso 3: vincular a Chatwoot -->
        <div v-if="isConnected" class="flex flex-col gap-2">
          <label for="inbox-name">Nombre del inbox en Chatwoot</label>
          <input
            id="inbox-name"
            v-model="inboxName"
            type="text"
            placeholder="ej: WhatsApp Cobranza"
          />
          <NextButton
            blue
            label="Conectar a Chatwoot"
            :is-loading="isLinking"
            :disabled="!canLinkToChatwoot"
            @click="linkToChatwoot"
          />
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>