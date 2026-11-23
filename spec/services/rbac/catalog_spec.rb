require 'rails_helper'

RSpec.describe Rbac::Catalog do
  it 'enforces only the six Contacts permissions and keeps the other modules planned' do
    entries = described_class.entries
    contacts_entries = entries.select { |entry| entry[:module] == 'contacts' }
    other_entries = entries.reject { |entry| entry[:module] == 'contacts' }
    contacts_keys = %w[contacts.read contacts.create contacts.update contacts.delete contacts.import contacts.export]

    expect(entries.map { |entry| entry[:module] }.uniq).to contain_exactly(
      'contacts', 'companies', 'reports', 'knowledge_base', 'campaigns', 'flows', 'triage'
    )
    expect(contacts_entries.pluck(:key)).to match_array(contacts_keys)
    expect(contacts_entries).to all(include(status: 'enforced', assignable: true))
    expect(other_entries).to all(include(status: 'planned', assignable: false))
    expect(entries.pluck(:description)).to all(be_present)
    expect(described_class.assignable_keys).to match_array(contacts_keys)
  end

  it 'does not let callers mutate catalog entries or their scope lists' do
    entry = described_class.entries.first

    expect { entry[:key].replace('elevated.permission') }.to raise_error(FrozenError)
    expect { entry[:scope_types] << 'selected_inboxes' }.to raise_error(FrozenError)
  end
end
