<script setup>
import { vOnClickOutside } from '@vueuse/components';
import { useToggle } from '@vueuse/core';
import { useMapGetter } from 'dashboard/composables/store';
import { computed, nextTick, ref, useTemplateRef } from 'vue';
import { I18nT, useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

const props = defineProps({
  conversationCount: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['select']);

const { t } = useI18n();
const containerRef = useTemplateRef('containerRef');
const [showDropdown, toggleDropdown] = useToggle(false);
const selectedTeam = ref(null);

const teams = useMapGetter('teams/getTeams');
const bulkActionsUiFlags = useMapGetter('bulkActions/getUIFlags');
const isUpdating = computed(() => bulkActionsUiFlags.value.isUpdating);

// Ver BulkAgentActions.vue para la explicación completa de por qué hace
// falta Teleport acá: esta barra vive dentro de un contenedor con
// "overflow-hidden" que recorta visualmente el menú sin importar su
// z-index. Teleport lo saca de ese contenedor, y calculamos la posición a
// mano porque al teleportar se pierde la ubicación relativa natural al botón.
const menuPosition = ref({ top: 0, left: 0 });
const MENU_WIDTH = 240;
const GAP = 8;

const calculateMenuPosition = () => {
  if (!containerRef.value) return;
  const rect = containerRef.value.getBoundingClientRect();

  let left = rect.right - MENU_WIDTH;
  if (left < GAP) left = rect.left;

  menuPosition.value = { top: rect.top - GAP, left };
};

const teamMenuItems = computed(() => {
  const items = [
    {
      action: 'select',
      value: 'none',
      label: t('BULK_ACTION.TEAMS.NONE'),
      isSelected: selectedTeam.value?.id === 0,
    },
  ];

  teams.value.forEach(team => {
    items.push({
      action: 'select',
      value: team.id,
      label: team.name,
      isSelected: selectedTeam.value?.id === team.id,
    });
  });

  return items;
});

const handleSelectTeam = item => {
  if (item.value === 'none') {
    selectedTeam.value = { id: 0, name: t('BULK_ACTION.TEAMS.NONE') };
  } else {
    const foundTeam = teams.value.find(team => team.id === item.value);
    selectedTeam.value = foundTeam || {
      id: 0,
      name: t('BULK_ACTION.TEAMS.NONE'),
    };
  }
};

const handleAssign = () => {
  if (isUpdating.value) return;
  emit('select', selectedTeam.value);
  selectedTeam.value = null;
  toggleDropdown(false);
};

const handleCancel = () => {
  selectedTeam.value = null;
};

const handleDismiss = () => {
  selectedTeam.value = null;
  toggleDropdown(false);
};

const handleToggleDropdown = async () => {
  const willOpen = !showDropdown.value;
  toggleDropdown();

  if (willOpen) {
    await nextTick();
    calculateMenuPosition();
  }
};
</script>

<template>
  <div ref="containerRef" class="relative">
    <Button
      v-tooltip="$t('BULK_ACTION.ASSIGN_TEAM_TOOLTIP')"
      icon="i-lucide-users-round"
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
          :menu-items="teamMenuItems"
          show-search
          :search-placeholder="t('BULK_ACTION.SEARCH_INPUT_PLACEHOLDER')"
          class="!fixed top-0 left-0 w-60 max-h-80"
          :style="{
            transform: `translate(${menuPosition.left}px, calc(${menuPosition.top}px - 100%))`,
          }"
          @action="handleSelectTeam"
        >
          <template v-if="selectedTeam" #footer>
            <div
              class="pt-2 pb-2 px-2 border-t border-n-weak sticky bottom-0 rounded-b-md z-20 bg-n-alpha-3 backdrop-blur-[4px]"
            >
              <div class="flex flex-col gap-2">
                <I18nT
                  v-if="selectedTeam.id"
                  keypath="BULK_ACTION.TEAMS.ASSIGN_TEAM_CONFIRMATION_LABEL"
                  tag="p"
                  class="text-xs text-n-slate-11 px-1 mb-0"
                  :plural="props.conversationCount"
                >
                  <template #n>
                    <strong class="text-n-slate-12">
                      {{ props.conversationCount }}
                    </strong>
                  </template>
                  <template #teamName>
                    <strong class="text-n-slate-12">
                      {{ selectedTeam.name }}
                    </strong>
                  </template>
                </I18nT>
                <I18nT
                  v-else
                  keypath="BULK_ACTION.TEAMS.UNASSIGN_TEAM_CONFIRMATION_LABEL"
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
