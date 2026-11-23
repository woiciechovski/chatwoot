require 'rails_helper'

RSpec.describe RbacAuditEvent do
  it 'stores sanitized mutation metadata and an explicit result' do
    event = described_class.new(
      account: create(:account),
      actor_type: 'AccountUser',
      actor_id: 42,
      action: 'rbac.role.created',
      target_type: 'RbacRole',
      target_id: 7,
      result: 'success',
      details: { 'name' => { 'to' => 'Support' } },
      request_id: 'request-123'
    )

    expect(event).to be_valid
  end

  it 'rejects results outside the audit contract' do
    event = described_class.new(
      account: create(:account),
      actor_type: 'System',
      action: 'rbac.role.updated',
      target_type: 'RbacRole',
      result: 'secret-payload'
    )

    expect(event).not_to be_valid
    expect(event.errors[:result]).to be_present
  end

  it 'requires an explicit actor when recording a denied operation' do
    account = create(:account)

    expect do
      Rbac::AuditEvents::Recorder.record_denied!(
        account: account,
        actor: nil,
        action: 'role.create.denied'
      )
    end.to raise_error(Rbac::AuditEvents::Recorder::MissingActorContextError)

    expect(described_class.where(account: account)).to be_empty
  end

  it 'does not convert a missing request actor into a system event' do
    account = create(:account)

    expect do
      Rbac::AuditEvents::Recorder.record_denied_safely!(
        account: account,
        actor: nil,
        action: 'role.create.denied'
      )
    end.not_to change(described_class, :count)

    expect(described_class.where(account: account, actor_type: 'System')).to be_empty
  end

  it 'only records a system actor when the caller explicitly requests one' do
    event = Rbac::AuditEvents::Recorder.record_denied!(
      account: create(:account),
      actor: nil,
      action: 'rbac.maintenance.denied',
      system: true
    )

    expect(event.actor_type).to eq('System')
    expect(event.actor_id).to be_nil
  end

  it 'does not let an audit insert failure escape a denied operation' do
    account = create(:account)
    actor = create(:user, account: account, role: :agent)
    allow(described_class).to receive(:create!).and_raise(ActiveRecord::RecordNotSaved)

    expect do
      Rbac::AuditEvents::Recorder.record_denied_safely!(
        account: account,
        actor: actor,
        action: 'role.create.denied'
      )
    end.not_to raise_error
  end
end
