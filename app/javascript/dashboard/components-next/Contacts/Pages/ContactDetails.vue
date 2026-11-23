<script setup>
import { computed, ref, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { useExactTimestamp } from 'shared/composables/useExactTimestamp';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ContactLabels from 'dashboard/components-next/Contacts/ContactLabels/ContactLabels.vue';
import ContactsForm from 'dashboard/components-next/Contacts/ContactsForm/ContactsForm.vue';
import ConfirmContactDeleteDialog from 'dashboard/components-next/Contacts/ContactsForm/ConfirmContactDeleteDialog.vue';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { useProtectedContactMedia } from 'dashboard/composables/useProtectedContactMedia';

const props = defineProps({
  selectedContact: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['goToContactsList']);

const exactTimestamp = useExactTimestamp();

const { t } = useI18n();
const store = useStore();
const { checkContactPermission } = usePolicy();
const { resolveProtectedContactMediaUrl } = useProtectedContactMedia();

const confirmDeleteContactDialogRef = ref(null);

const avatarFile = ref(null);
const avatarUrl = ref('');

const contactsFormRef = ref(null);

const uiFlags = useMapGetter('contacts/getUIFlags');
const isUpdating = computed(() => uiFlags.value.isUpdating);

const isFormInvalid = computed(() => contactsFormRef.value?.isFormInvalid);
const canUpdateContacts = computed(() =>
  checkContactPermission('contacts.update')
);
const canDeleteContacts = computed(() =>
  checkContactPermission('contacts.delete')
);

const contactData = ref({});
const protectedAvatarUrl = ref('');

const getInitialContactData = () => {
  if (!props.selectedContact) return {};
  return { ...props.selectedContact };
};

const clearProtectedContactData = contactId => {
  contactData.value = { id: contactId };
  avatarFile.value = null;
  avatarUrl.value = '';
  protectedAvatarUrl.value = '';
  emit('goToContactsList');
};

const isMinimalContactResponse = contact =>
  Boolean(contact) && Object.keys(contact).every(key => key === 'id');

onMounted(() => {
  Object.assign(contactData.value, getInitialContactData());
});

const createdAt = computed(() => {
  return contactData.value?.createdAt
    ? dynamicTime(contactData.value.createdAt)
    : '';
});

const lastActivityAt = computed(() => {
  return contactData.value?.lastActivityAt
    ? dynamicTime(contactData.value.lastActivityAt)
    : '';
});

const avatarSrc = computed(() => {
  return avatarUrl.value ? avatarUrl.value : protectedAvatarUrl.value;
});

watch(
  () => contactData.value?.thumbnail,
  async sourceUrl => {
    protectedAvatarUrl.value = await resolveProtectedContactMediaUrl(sourceUrl);
  },
  { immediate: true }
);

const handleFormUpdate = updatedData => {
  Object.assign(contactData.value, updatedData);
};

const updateContact = async () => {
  try {
    const { customAttributes, ...basicContactData } = contactData.value;
    const updatedContact = await store.dispatch('contacts/update', {
      ...basicContactData,
      resolveLegacyCompany: true,
    });
    if (isMinimalContactResponse(updatedContact)) {
      clearProtectedContactData(updatedContact.id);
      return;
    }
    contactData.value = { ...updatedContact };
    await store.dispatch(
      'contacts/fetchContactableInbox',
      props.selectedContact.id
    );
    useAlert(t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.ERROR_MESSAGE'));
  }
};

const openConfirmDeleteContactDialog = () => {
  confirmDeleteContactDialogRef.value?.dialogRef.open();
};

const handleAvatarUpload = async ({ file, url }) => {
  avatarFile.value = file;
  avatarUrl.value = url;

  try {
    const updatedContact = await store.dispatch('contacts/update', {
      ...contactsFormRef.value?.state,
      avatar: file,
      isFormData: true,
    });
    if (isMinimalContactResponse(updatedContact)) {
      clearProtectedContactData(updatedContact.id);
      return;
    }
    useAlert(t('CONTACTS_LAYOUT.DETAILS.AVATAR.UPLOAD.SUCCESS_MESSAGE'));
  } catch {
    useAlert(t('CONTACTS_LAYOUT.DETAILS.AVATAR.UPLOAD.ERROR_MESSAGE'));
  }
};

const handleAvatarDelete = async () => {
  try {
    if (props.selectedContact && props.selectedContact.id) {
      const updatedContact = await store.dispatch(
        'contacts/deleteAvatar',
        props.selectedContact.id
      );
      if (isMinimalContactResponse(updatedContact)) {
        clearProtectedContactData(updatedContact.id);
        return;
      }
      useAlert(t('CONTACTS_LAYOUT.DETAILS.AVATAR.DELETE.SUCCESS_MESSAGE'));
    }
    avatarFile.value = null;
    avatarUrl.value = '';
    contactData.value.thumbnail = null;
  } catch (error) {
    useAlert(
      error.message
        ? error.message
        : t('CONTACTS_LAYOUT.DETAILS.AVATAR.DELETE.ERROR_MESSAGE')
    );
  }
};
</script>

<template>
  <div class="flex flex-col items-start gap-8 pb-6">
    <div class="flex flex-col items-start gap-3">
      <Avatar
        :src="avatarSrc || ''"
        :name="selectedContact?.name || ''"
        :size="72"
        :allow-upload="canUpdateContacts"
        @upload="handleAvatarUpload"
        @delete="handleAvatarDelete"
      />
      <div class="flex flex-col gap-1">
        <h3 class="text-base font-medium text-n-slate-12">
          {{ selectedContact?.name }}
        </h3>
        <div class="flex flex-col gap-1.5">
          <span
            v-if="selectedContact?.identifier"
            class="inline-flex items-center gap-1 text-sm text-n-slate-11"
          >
            <span class="i-ph-user-gear text-n-slate-10 size-4" />
            {{ selectedContact?.identifier }}
          </span>
          <span class="inline-flex items-center gap-1 text-sm text-n-slate-11">
            <span
              v-if="selectedContact?.identifier"
              class="i-ph-activity text-n-slate-10 size-4"
            />
            <span
              v-tooltip.top="{
                content: exactTimestamp(contactData?.createdAt),
                delay: { show: 500, hide: 0 },
              }"
            >
              {{
                $t('CONTACTS_LAYOUT.DETAILS.CREATED_AT', { date: createdAt })
              }}
            </span>
            •
            <span
              v-tooltip.top="{
                content: exactTimestamp(contactData?.lastActivityAt),
                delay: { show: 500, hide: 0 },
              }"
            >
              {{
                $t('CONTACTS_LAYOUT.DETAILS.LAST_ACTIVITY', {
                  date: lastActivityAt,
                })
              }}
            </span>
          </span>
        </div>
      </div>
      <ContactLabels
        :contact-id="selectedContact?.id"
        :read-only="!canUpdateContacts"
      />
    </div>
    <div class="flex flex-col items-start gap-6">
      <ContactsForm
        ref="contactsFormRef"
        :contact-data="contactData"
        is-details-view
        :read-only="!canUpdateContacts"
        @update="handleFormUpdate"
      />
      <Button
        v-if="canUpdateContacts"
        :label="t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.UPDATE_BUTTON')"
        size="sm"
        :is-loading="isUpdating"
        :disabled="isUpdating || isFormInvalid"
        @click="updateContact"
      />
    </div>
    <div v-if="canDeleteContacts">
      <div
        class="flex flex-col items-start w-full gap-4 pt-6 border-t border-n-strong"
      >
        <div class="flex flex-col gap-2">
          <h6 class="text-base font-medium text-n-slate-12">
            {{ t('CONTACTS_LAYOUT.DETAILS.DELETE_CONTACT') }}
          </h6>
          <span class="text-sm text-n-slate-11">
            {{ t('CONTACTS_LAYOUT.DETAILS.DELETE_CONTACT_DESCRIPTION') }}
          </span>
        </div>
        <Button
          :label="t('CONTACTS_LAYOUT.DETAILS.DELETE_CONTACT')"
          color="ruby"
          @click="openConfirmDeleteContactDialog"
        />
      </div>
      <ConfirmContactDeleteDialog
        ref="confirmDeleteContactDialogRef"
        :selected-contact="selectedContact"
        @go-to-contacts-list="emit('goToContactsList')"
      />
    </div>
  </div>
</template>
