import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import FlowManager from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/flows'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'conversation_flows_index',
          component: FlowManager,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
