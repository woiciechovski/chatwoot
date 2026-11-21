import { frontendURL } from '../../../helper/URLHelper';
import TriageView from './TriageView.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/triage'),
      name: 'triage_index',
      component: TriageView,
      meta: {
        permissions: ['administrator'],
      },
    },
  ],
};
