import { computed, reactive, unref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useConfig } from 'dashboard/composables/useConfig';
import ContactAPI from 'dashboard/api/contacts';
import {
  getUserPermissions,
  hasPermissions,
} from 'dashboard/helper/permissionsHelper';
import {
  CLOUD_PAYWALLED_FEATURES,
  PREMIUM_FEATURES,
} from 'dashboard/featureFlags';

import { INSTALLATION_TYPES } from 'dashboard/constants/installationTypes';

const CONTACT_CAPABILITIES_TTL = 15000;
const contactCapabilitiesByAccountUser = reactive({});
const pendingCapabilityRequests = new Map();

export function usePolicy() {
  const user = useMapGetter('getCurrentUser');
  const isFeatureEnabled = useMapGetter('accounts/isFeatureEnabledonAccount');
  const isOnChatwootCloud = useMapGetter('globalConfig/isOnChatwootCloud');
  const isACustomBrandedInstance = useMapGetter(
    'globalConfig/isACustomBrandedInstance'
  );

  const { isEnterprise, enterprisePlanName } = useConfig();
  const { accountId } = useAccount();

  const getCapabilityCacheKey = () => {
    const currentUser = user.value;
    if (!accountId.value || !currentUser?.id) return null;
    return `${accountId.value}:${currentUser.id}`;
  };

  const refreshContactCapabilities = () => {
    const cacheKey = getCapabilityCacheKey();
    if (!cacheKey) return Promise.resolve();

    const cached = contactCapabilitiesByAccountUser[cacheKey];
    if (cached?.expiresAt > Date.now()) return Promise.resolve();
    if (pendingCapabilityRequests.has(cacheKey)) {
      return pendingCapabilityRequests.get(cacheKey);
    }

    contactCapabilitiesByAccountUser[cacheKey] = {
      capabilities: cached?.capabilities || null,
      expiresAt: Date.now() + CONTACT_CAPABILITIES_TTL,
    };
    const request = ContactAPI.getCapabilities(accountId.value)
      .then(({ data }) => {
        const contactsDomain = data.domains?.find(
          domain => domain.module === 'contacts'
        );
        contactCapabilitiesByAccountUser[cacheKey] = {
          capabilities: contactsDomain?.capabilities || null,
          expiresAt: Date.now() + CONTACT_CAPABILITIES_TTL,
        };
      })
      .catch(() => {
        contactCapabilitiesByAccountUser[cacheKey] = {
          capabilities: null,
          expiresAt: Date.now() + CONTACT_CAPABILITIES_TTL,
        };
      })
      .finally(() => pendingCapabilityRequests.delete(cacheKey));

    pendingCapabilityRequests.set(cacheKey, request);
    return request;
  };

  const getUserPermissionsForAccount = () => {
    return getUserPermissions(user.value, accountId.value);
  };

  const isFeatureFlagEnabled = featureFlag => {
    if (!featureFlag) return true;
    return isFeatureEnabled.value(accountId.value, featureFlag);
  };

  const checkPermissions = requiredPermissions => {
    if (!requiredPermissions || !requiredPermissions.length) return true;
    const userPermissions = getUserPermissionsForAccount();
    return hasPermissions(requiredPermissions, userPermissions);
  };

  const legacyContactPermission = permission => {
    if (
      ['contacts.delete', 'contacts.import', 'contacts.export'].includes(
        permission
      )
    ) {
      return checkPermissions(['administrator', 'contact_manage']);
    }

    return true;
  };

  const checkContactPermissions = requiredPermissions => {
    if (!requiredPermissions || !requiredPermissions.length) return true;
    const cacheKey = getCapabilityCacheKey();
    const cached = cacheKey ? contactCapabilitiesByAccountUser[cacheKey] : null;
    if (!cached || cached.expiresAt <= Date.now()) {
      refreshContactCapabilities();
    }

    const capabilities = cached?.capabilities;
    return requiredPermissions.every(permission => {
      if (capabilities && Object.hasOwn(capabilities, permission)) {
        return capabilities[permission] === true;
      }
      return legacyContactPermission(permission);
    });
  };

  const checkContactPermission = permission =>
    checkContactPermissions([permission]);

  const checkInstallationType = config => {
    if (Array.isArray(config) && config.length > 0) {
      const installationCheck = {
        [INSTALLATION_TYPES.ENTERPRISE]: isEnterprise,
        [INSTALLATION_TYPES.CLOUD]: isOnChatwootCloud.value,
        [INSTALLATION_TYPES.COMMUNITY]: true,
      };

      return config.some(type => installationCheck[type]);
    }

    return true;
  };

  const isCloudPaywalledFeature = featureFlag =>
    CLOUD_PAYWALLED_FEATURES.includes(featureFlag);

  const isPremiumFeature = featureFlag => {
    if (!featureFlag) return true;
    return PREMIUM_FEATURES.includes(featureFlag);
  };

  const hasPremiumEnterprise = computed(() => {
    if (isEnterprise) return enterprisePlanName !== 'community';

    return true;
  });

  const shouldShow = (featureFlag, permissions, installationTypes) => {
    const flag = unref(featureFlag);
    const perms = unref(permissions);
    const installation = unref(installationTypes);

    // if the user does not have permissions or installation type is not supported
    // return false;
    // This supersedes everything
    if (!checkPermissions(perms)) return false;
    if (!checkInstallationType(installation)) return false;

    if (isACustomBrandedInstance.value) {
      // if this is a custom branded instance, we just use the feature flag as a reference
      return isFeatureFlagEnabled(flag);
    }

    // if on cloud, we should if the feature is allowed
    // or if the feature is a premium one like SLA to show a paywall
    // the paywall should be managed by the individual component
    if (isOnChatwootCloud.value) {
      return (
        isFeatureFlagEnabled(flag) ||
        isPremiumFeature(flag) ||
        isCloudPaywalledFeature(flag)
      );
    }

    if (isEnterprise) {
      // in enterprise, if the feature is premium but they don't have an enterprise plan
      // we should it anyway this is to show upsells on enterprise regardless of the feature flag
      // Feature flag is only honored if they have a premium plan
      //
      // In case they have a premium plan, the check on feature flag alone is enough
      // because the second condition will always be false
      // That means once subscribed, the feature can be disabled by the admin
      //
      // the paywall should be managed by the individual component
      return (
        isFeatureFlagEnabled(flag) ||
        (isPremiumFeature(flag) && !hasPremiumEnterprise.value)
      );
    }

    // default to true
    return true;
  };

  const shouldShowPaywall = featureFlag => {
    const flag = unref(featureFlag);
    if (!flag) return false;

    if (isACustomBrandedInstance.value) {
      // custom branded instances never show paywall
      return false;
    }

    if (isCloudPaywalledFeature(flag)) {
      return isOnChatwootCloud.value && !isFeatureFlagEnabled(flag);
    }

    if (isPremiumFeature(flag)) {
      if (isOnChatwootCloud.value) {
        return !isFeatureFlagEnabled(flag);
      }

      if (isEnterprise) {
        return !hasPremiumEnterprise.value;
      }
    }

    return false;
  };

  return {
    checkPermissions,
    checkContactPermission,
    checkContactPermissions,
    refreshContactCapabilities,
    checkInstallationType,
    shouldShowPaywall,
    isFeatureFlagEnabled,
    shouldShow,
  };
}
