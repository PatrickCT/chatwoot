<script setup>
import { vOnClickOutside } from '@vueuse/components';
import { useToggle } from '@vueuse/core';
import { useMapGetter } from 'dashboard/composables/store';
import { computed, nextTick, ref, useTemplateRef } from 'vue';
import { I18nT, useI18n } from 'vue-i18n';
import { useStore } from 'vuex';

import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

const props = defineProps({
  selectedInboxes: {
    type: Array,
    default: () => [],
  },
  conversationCount: {
    type: Number,
    default: 0,
  },
});

const emit = defineEmits(['select']);

const { t } = useI18n();
const store = useStore();

const containerRef = useTemplateRef('containerRef');
const [showDropdown, toggleDropdown] = useToggle(false);
const selectedAgent = ref(null);

// El menú se saca del flujo normal con <Teleport to="body"> porque esta
// barra vive dentro de un contenedor con "overflow-hidden" (el panel de
// chats), que recorta visualmente cualquier cosa que se salga de sus
// límites SIN IMPORTAR el z-index — no es un problema de apilamiento, es
// que el navegador directamente no dibuja lo que sobresale. Teleport mueve
// el nodo real al final del <body>, escapando de ese recorte. Como al
// teleportar se pierde la posición relativa natural al botón, la
// calculamos a mano con getBoundingClientRect() — mismo patrón que ya usa
// SidebarCollapsedPopover en este proyecto para el mismo tipo de problema.
const menuPosition = ref({ top: 0, left: 0 });

const MENU_WIDTH = 240; // coincide con el w-60 que ya tenía el menú
const GAP = 8; // separación entre el botón y el menú

const calculateMenuPosition = () => {
  if (!containerRef.value) return;

  const rect = containerRef.value.getBoundingClientRect();

  // Por defecto, el menú se abre hacia arriba y alineado a la derecha del
  // botón (como estaba antes visualmente). Si no entra a la derecha
  // (se saldría de la pantalla), lo alineamos a la izquierda en su lugar.
  let left = rect.right - MENU_WIDTH;
  if (left < GAP) {
    left = rect.left;
  }

  menuPosition.value = {
    top: rect.top - GAP, // el CSS lo traduce a "termina GAP arriba del botón" vía transform
    left,
  };
};

const assignableAgentsUiFlags = useMapGetter(
  'inboxAssignableAgents/getUIFlags'
);
const bulkActionsUiFlags = useMapGetter('bulkActions/getUIFlags');

const isLoading = computed(() => assignableAgentsUiFlags.value.isFetching);
const isUpdating = computed(() => bulkActionsUiFlags.value.isUpdating);

const assignableAgentsList = useMapGetter(
  'inboxAssignableAgents/getAssignableAgents'
);
const assignableAgents = computed(() =>
  assignableAgentsList.value(props.selectedInboxes.join(','))
);

const agentMenuItems = computed(() => {
  const items = [
    {
      action: 'select',
      value: 'none',
      label: t('BULK_ACTION.NONE'),
      thumbnail: {
        name: t('BULK_ACTION.NONE'),
        src: '',
      },
      isSelected: selectedAgent.value?.id === null,
    },
  ];

  assignableAgents.value.forEach(agent => {
    items.push({
      action: 'select',
      value: agent.id,
      label: agent.name,
      thumbnail: {
        name: agent.name,
        src: agent.thumbnail,
      },
      isSelected: selectedAgent.value?.id === agent.id,
    });
  });

  return items;
});

const handleSelectAgent = item => {
  if (item.value === 'none') {
    selectedAgent.value = { id: null, name: t('BULK_ACTION.NONE') };
  } else {
    const agent = assignableAgents.value.find(a => a.id === item.value);
    selectedAgent.value = agent || { id: null, name: t('BULK_ACTION.NONE') };
  }
};

const handleAssign = () => {
  if (isUpdating.value) return;
  emit('select', selectedAgent.value);
  selectedAgent.value = null;
  toggleDropdown(false);
};

const handleCancel = () => {
  selectedAgent.value = null;
};

const handleDismiss = () => {
  selectedAgent.value = null;
  toggleDropdown(false);
};

const handleToggleDropdown = async () => {
  const willOpen = !showDropdown.value;
  toggleDropdown();

  if (willOpen) {
    // Esperamos al próximo tick para que containerRef ya tenga su tamaño
    // final antes de medirlo.
    await nextTick();
    calculateMenuPosition();

    if (props.selectedInboxes.length > 0) {
      store.dispatch('inboxAssignableAgents/fetch', props.selectedInboxes);
    }
  }
};
</script>

<template>
  <div ref="containerRef" class="relative">
    <Button
      v-tooltip="$t('BULK_ACTION.ASSIGN_AGENT_TOOLTIP')"
      icon="i-lucide-user-round-check"
      slate
      xs
      ghost
      :class="{ 'bg-n-alpha-2': showDropdown }"
      @click="handleToggleDropdown"
    />
    <Teleport to="body">
      <Transition
        enter-active-class="transition-all duration-150 ease-out origin-bottom"
        enter-from-class="opacity-0 scale-95"
        enter-to-class="opacity-100 scale-100"
        leave-active-class="transition-all duration-100 ease-in origin-bottom"
        leave-from-class="opacity-100 scale-100"
        leave-to-class="opacity-0 scale-95"
      >
        <DropdownMenu
          v-if="showDropdown"
          v-on-click-outside="[handleDismiss, { ignore: [containerRef] }]"
          :menu-items="agentMenuItems"
          :is-loading="isLoading"
          show-search
          :search-placeholder="t('BULK_ACTION.SEARCH_INPUT_PLACEHOLDER')"
          class="!fixed top-0 left-0 w-60 max-h-80"
          :style="{
            transform: `translate(${menuPosition.left}px, calc(${menuPosition.top}px - 100%))`,
          }"
          @action="handleSelectAgent"
        >
          <template v-if="selectedAgent" #footer>
            <div
              class="pt-2 pb-2 px-2 border-t border-n-weak sticky bottom-0 rounded-b-md z-20 bg-n-alpha-3 backdrop-blur-[4px]"
            >
              <div class="flex flex-col gap-2">
                <I18nT
                  v-if="selectedAgent.id"
                  keypath="BULK_ACTION.ASSIGN_AGENT_CONFIRMATION_LABEL"
                  tag="p"
                  class="text-xs text-n-slate-11 px-1 mb-0"
                  :plural="props.conversationCount"
                >
                  <template #n>
                    <strong class="text-n-slate-12">
                      {{ props.conversationCount }}
                    </strong>
                  </template>
                  <template #agentName>
                    <strong class="text-n-slate-12">
                      {{ selectedAgent.name }}
                    </strong>
                  </template>
                </I18nT>
                <I18nT
                  v-else
                  keypath="BULK_ACTION.UNASSIGN_AGENT_CONFIRMATION_LABEL"
                  tag="p"
                  class="text-xs text-n-slate-11 px-1 mb-0"
                  :plural="props.conversationCount"
                >
                  <template #n>
                    <strong class="text-n-slate-12">
                      {{ props.conversationCount }}
                    </strong>
                  </template>
                </I18nT>
                <div class="flex gap-2">
                  <Button
                    sm
                    faded
                    slate
                    class="flex-1"
                    :label="t('BULK_ACTION.CANCEL')"
                    @click="handleCancel"
                  />
                  <Button
                    sm
                    class="flex-1"
                    :label="t('BULK_ACTION.YES')"
                    :disabled="isUpdating"
                    :is-loading="isUpdating"
                    @click="handleAssign"
                  />
                </div>
              </div>
            </div>
          </template>
        </DropdownMenu>
      </Transition>
    </Teleport>
  </div>
</template>
