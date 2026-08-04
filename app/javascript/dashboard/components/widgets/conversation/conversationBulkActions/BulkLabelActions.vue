<script setup>
import { vOnClickOutside } from '@vueuse/components';
import { useToggle } from '@vueuse/core';
import { useMapGetter } from 'dashboard/composables/store';
import { computed, nextTick, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';

import NextButton from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  type: {
    type: String,
    default: 'conversation',
  },
  action: {
    type: String,
    default: 'assign',
    validator: value => ['assign', 'remove'].includes(value),
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
  appliedLabels: {
    type: Array,
    default: null,
  },
});

const emit = defineEmits(['assign', 'remove']);

const { t } = useI18n();

const labels = useMapGetter('labels/getLabels');

const containerRef = useTemplateRef('containerRef');
const [showDropdown, toggleDropdown] = useToggle(false);
const selectedLabels = ref([]);

const isTypeContact = computed(() => props.type === 'contact');
const isRemoveAction = computed(() => props.action === 'remove');

// Este menú se usa en dos lugares distintos: la barra de bulk actions de
// conversaciones (type="conversation", el que sabemos que queda atrapado
// detrás del sidebar por el overflow-hidden del panel de chats — ver
// BulkAgentActions.vue para la explicación completa) y la vista de
// contactos (type="contact"), que nunca reportó este problema. Por eso el
// Teleport solo se activa para el primer caso — no tocamos lo que ya
// funciona bien.
const menuPosition = ref({ top: 0, left: 0 });
const MENU_WIDTH = 240;
const GAP = 8;

const calculateMenuPosition = () => {
  if (!containerRef.value || isTypeContact.value) return;
  const rect = containerRef.value.getBoundingClientRect();

  let left = rect.right - MENU_WIDTH;
  if (left < GAP) left = rect.left;

  menuPosition.value = { top: rect.top - GAP, left };
};

const buttonLabel = computed(() => {
  if (!isTypeContact.value) return '';

  return isRemoveAction.value
    ? t('CONTACTS_BULK_ACTIONS.REMOVE_LABELS')
    : t('CONTACTS_BULK_ACTIONS.ASSIGN_LABELS');
});

const tooltipLabel = computed(() =>
  isRemoveAction.value
    ? t('BULK_ACTION.LABELS.REMOVE_LABELS')
    : t('BULK_ACTION.LABELS.ASSIGN_LABELS')
);

const confirmLabel = computed(() =>
  isRemoveAction.value
    ? t('BULK_ACTION.LABELS.REMOVE_SELECTED_LABELS')
    : t('BULK_ACTION.LABELS.ASSIGN_SELECTED_LABELS')
);

const isLabelSelected = labelTitle => {
  return selectedLabels.value.includes(labelTitle);
};

const visibleLabels = computed(() => {
  if (!isRemoveAction.value || props.appliedLabels === null) {
    return labels.value;
  }

  const applied = new Set(props.appliedLabels);
  return labels.value.filter(label => applied.has(label.title));
});

const labelMenuItems = computed(() => {
  return visibleLabels.value.map(label => ({
    action: 'select',
    value: label.title,
    label: label.title,
    color: label.color,
    id: label.id,
    isSelected: isLabelSelected(label.title),
  }));
});

const toggleLabelSelection = labelTitle => {
  const index = selectedLabels.value.indexOf(labelTitle);
  if (index > -1) {
    selectedLabels.value.splice(index, 1);
  } else {
    selectedLabels.value.push(labelTitle);
  }
};

const handleApply = () => {
  if (selectedLabels.value.length > 0) {
    if (isRemoveAction.value) {
      emit('remove', selectedLabels.value);
    } else {
      emit('assign', selectedLabels.value);
    }
    toggleDropdown(false);
    selectedLabels.value = [];
  }
};

const handleDismiss = () => {
  selectedLabels.value = [];
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
    <NextButton
      v-tooltip="tooltipLabel"
      :label="buttonLabel"
      :icon="isRemoveAction ? 'i-woot-tag-remove' : 'i-lucide-tag'"
      slate
      :size="isTypeContact ? 'sm' : 'xs'"
      ghost
      :class="{
        'bg-n-alpha-2': showDropdown,
        '[&>span:nth-child(2)]:hidden md:[&>span:nth-child(2)]:inline w-fit !text-n-blue-11 [&>span]:!text-n-blue-11 !px-2':
          isTypeContact,
      }"
      :disabled="disabled || isLoading"
      :is-loading="isLoading"
      @click="handleToggleDropdown"
    />
    <Teleport to="body" :disabled="isTypeContact">
      <Transition
        :enter-active-class="
          !isTypeContact
            ? 'transition-all duration-150 ease-out origin-bottom'
            : 'transition-all duration-150 ease-out origin-top'
        "
        enter-from-class="opacity-0 scale-95"
        enter-to-class="opacity-100 scale-100"
        :leave-active-class="
          !isTypeContact
            ? 'transition-all duration-100 ease-in origin-bottom'
            : 'transition-all duration-100 ease-in origin-top'
        "
        leave-from-class="opacity-100 scale-100"
        leave-to-class="opacity-0 scale-95"
      >
        <DropdownMenu
          v-if="showDropdown"
          v-on-click-outside="[handleDismiss, { ignore: [containerRef] }]"
          :menu-items="labelMenuItems"
          show-search
          :search-placeholder="t('BULK_ACTION.SEARCH_INPUT_PLACEHOLDER')"
          class="w-60 max-h-80"
          :class="
            isTypeContact
              ? 'ltr:right-0 rtl:left-0 mb-1 top-10'
              : '!fixed top-0 left-0'
          "
          :style="
            isTypeContact
              ? undefined
              : {
                  transform: `translate(${menuPosition.left}px, calc(${menuPosition.top}px - 100%))`,
                }
          "
          @action="item => toggleLabelSelection(item.value)"
        >
          <template #thumbnail="{ item }">
            <span
              class="rounded-md h-3 w-3 flex-shrink-0 border border-solid border-n-weak"
              :style="{ backgroundColor: item.color }"
            />
          </template>

          <template #trailing-icon="{ item }">
            <Icon
              v-if="isLabelSelected(item.value)"
              icon="i-lucide-check"
              class="size-4 text-n-blue-11 flex-shrink-0"
            />
          </template>

          <template #footer>
            <div
              class="sticky bottom-0 rounded-b-md px-2 py-2 z-20 bg-n-alpha-3 backdrop-blur-[4px]"
            >
              <NextButton
                sm
                class="w-full [&>span:nth-child(2)]:hidden md:[&>span:nth-child(2)]:inline-flex"
                :label="confirmLabel"
                :disabled="!selectedLabels.length"
                @click="handleApply"
              />
            </div>
          </template>
        </DropdownMenu>
      </Transition>
    </Teleport>
  </div>
</template>
