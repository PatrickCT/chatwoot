<script setup>
import { useBulkActions } from 'dashboard/composables/chatlist/useBulkActions.js';
import { useMapGetter } from 'dashboard/composables/store.js';
import wootConstants from 'dashboard/constants/globals';
import {
  CMD_BULK_ACTION_REOPEN_CONVERSATION,
  CMD_BULK_ACTION_RESOLVE_CONVERSATION,
  CMD_BULK_ACTION_SNOOZE_CONVERSATION,
} from 'dashboard/helper/commandbar/events';
import { findSnoozeTime } from 'dashboard/helper/snoozeHelpers';
import { getUnixTime } from 'date-fns';
import { emitter } from 'shared/helpers/mitt';
import { computed, onMounted, onUnmounted, ref, useAttrs } from 'vue';

import NextButton from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import CustomSnoozeModal from 'dashboard/components/CustomSnoozeModal.vue';
import BulkAgentActions from './BulkAgentActions.vue';
import BulkLabelActions from './BulkLabelActions.vue';
import BulkTeamActions from './BulkTeamActions.vue';
import BulkUpdateActions from './BulkUpdateActions.vue';

const props = defineProps({
  conversations: {
    type: Array,
    default: () => [],
  },
  allConversationsSelected: {
    type: Boolean,
    default: false,
  },
  selectedInboxes: {
    type: Array,
    default: () => [],
  },
  showOpenAction: {
    type: Boolean,
    default: false,
  },
  showResolvedAction: {
    type: Boolean,
    default: false,
  },
  showSnoozedAction: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['selectAllConversations']);

defineOptions({
  inheritAttrs: false,
});

const attrs = useAttrs();

const {
  selectedConversations,
  onAssignAgent,
  onAssignLabels,
  onRemoveLabels,
  onAssignTeamsForBulk: onAssignTeam,
  onUpdateConversations,
} = useBulkActions();

const getConversationById = useMapGetter('getConversationById');

const appliedLabelsForSelection = computed(() => {
  const applied = new Set();
  selectedConversations.value.forEach(id => {
    const conversation = getConversationById.value(id);
    (conversation?.labels || []).forEach(label => applied.add(label));
  });
  return Array.from(applied);
});

const showCustomTimeSnoozeModal = ref(false);

function onCmdSnoozeConversation(snoozeType) {
  if (snoozeType === wootConstants.SNOOZE_OPTIONS.UNTIL_CUSTOM_TIME) {
    showCustomTimeSnoozeModal.value = true;
  } else if (typeof snoozeType === 'number') {
    onUpdateConversations('snoozed', snoozeType);
  } else {
    onUpdateConversations('snoozed', findSnoozeTime(snoozeType) || null);
  }
}

function onCmdReopenConversation() {
  onUpdateConversations('open', null);
}

function onCmdResolveConversation() {
  onUpdateConversations('resolved', null);
}

function customSnoozeTime(customSnoozedTime) {
  showCustomTimeSnoozeModal.value = false;
  if (customSnoozedTime) {
    onUpdateConversations('snoozed', getUnixTime(customSnoozedTime));
  }
}

function hideCustomSnoozeModal() {
  showCustomTimeSnoozeModal.value = false;
}

// Computed property with getter/setter to enable v-model usage
const allSelected = computed({
  get: () => props.allConversationsSelected,
  set: value => {
    emit('selectAllConversations', value);
  },
});

onMounted(() => {
  emitter.on(CMD_BULK_ACTION_SNOOZE_CONVERSATION, onCmdSnoozeConversation);
  emitter.on(CMD_BULK_ACTION_REOPEN_CONVERSATION, onCmdReopenConversation);
  emitter.on(CMD_BULK_ACTION_RESOLVE_CONVERSATION, onCmdResolveConversation);
});

onUnmounted(() => {
  emitter.off(CMD_BULK_ACTION_SNOOZE_CONVERSATION, onCmdSnoozeConversation);
  emitter.off(CMD_BULK_ACTION_REOPEN_CONVERSATION, onCmdReopenConversation);
  emitter.off(CMD_BULK_ACTION_RESOLVE_CONVERSATION, onCmdResolveConversation);
});
</script>

<template>
  <Transition
    enter-active-class="transition-all duration-200 ease-out origin-bottom"
    enter-from-class="opacity-0 scale-95 translate-y-2"
    enter-to-class="opacity-100 scale-100 translate-y-0"
    leave-active-class="transition-all duration-150 ease-in origin-bottom"
    leave-from-class="opacity-100 scale-100 translate-y-0"
    leave-to-class="opacity-0 scale-95 translate-y-2"
  >
    <!--
      OJO: no agregar "left-1/2 -translate-x-1/2" acá — como el contenedor
      ya usa w-full, ese transform no cambia nada visualmente (matemáticamente
      da lo mismo que no ponerlo), pero SÍ crea un contexto de apilamiento
      nuevo. No es la causa principal del problema del z-index (ver nota de
      z-50 abajo), pero mejor no reintroducirlo.

      OJO 2 — la causa REAL de que este menú apareciera detrás del sidebar:
      Sidebar.vue tiene z-40 fijo. Esta barra tenía z-30, así que SIEMPRE
      iba a perder contra el sidebar sin importar nada más — no hacía falta
      ningún problema de contexto de apilamiento para explicarlo, era
      simplemente z-30 < z-40. Por eso ahora es z-50.
    -->
    <div
      v-if="conversations.length > 0"
      v-bind="attrs"
      class="px-2 absolute bottom-20 sm:bottom-4 z-50 w-full origin-bottom"
    >
      <div
        v-if="allConversationsSelected"
        class="bg-n-amber-2 outline -outline-offset-1 outline-1 outline-n-amber-5 rounded-lg text-sm mb-2 py-1.5 px-2 text-n-amber-text"
      >
        {{ $t('BULK_ACTION.ALL_CONVERSATIONS_SELECTED_ALERT') }}
      </div>
      <div
        class="flex flex-wrap items-center justify-between gap-2 p-2 bg-n-button-color outline outline-1 -outline-offset-1 rounded-[10px] outline-n-weak shadow-[0_0_12px_0_rgba(27,40,59,0.08)]"
      >
        <div
          class="ltr:ml-0.5 rtl:mr-0.5 flex items-center gap-1 flex-wrap min-w-0"
        >
          <label class="cursor-pointer flex items-center gap-1.5">
            <Checkbox
              v-model="allSelected"
              :indeterminate="!allConversationsSelected"
            />
            <span class="cursor-pointer">
              {{
                $t('BULK_ACTION.CONVERSATIONS_SELECTED', {
                  conversationCount: conversations.length,
                })
              }}
            </span>
          </label>
          <div class="w-px h-3 bg-n-weak rounded-lg ltr:ml-1 rtl:mr-1" />
          <NextButton
            v-tooltip="$t('BULK_ACTION.CLEAR_SELECTION')"
            :label="$t('BULK_ACTION.CLEAR_SELECTION')"
            ghost
            class="!text-n-blue-11 !px-1 !h-6 whitespace-nowrap"
            sm
            @click="allSelected = false"
          />
        </div>
        <div class="flex items-center gap-2 flex-wrap">
          <BulkLabelActions @assign="onAssignLabels" />
          <BulkLabelActions
            action="remove"
            :applied-labels="appliedLabelsForSelection"
            @remove="onRemoveLabels"
          />
          <BulkUpdateActions
            :show-resolve="!showResolvedAction"
            :show-reopen="!showOpenAction"
            :show-snooze="!showSnoozedAction"
            @update="onUpdateConversations"
          />
          <BulkAgentActions
            :selected-inboxes="selectedInboxes"
            :conversation-count="conversations.length"
            @select="onAssignAgent"
          />
          <BulkTeamActions
            :conversation-count="conversations.length"
            @select="onAssignTeam"
          />
        </div>
      </div>
    </div>
  </Transition>
  <woot-modal
    v-model:show="showCustomTimeSnoozeModal"
    :on-close="hideCustomSnoozeModal"
  >
    <CustomSnoozeModal
      @close="hideCustomSnoozeModal"
      @choose-time="customSnoozeTime"
    />
  </woot-modal>
</template>
