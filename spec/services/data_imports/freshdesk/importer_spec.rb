require 'rails_helper'

RSpec.describe DataImports::Freshdesk::Importer do
  let(:account) { create(:account) }
  let(:data_import) { create(:data_import, :freshdesk, account: account) }
  let(:client) { instance_double(DataImports::Freshdesk::Client) }
  let(:contact_payload) do
    JSON.parse(Rails.root.join('spec/fixtures/data_import/freshdesk/contact.json').read)
  end
  let(:ticket_fixture) do
    JSON.parse(Rails.root.join('spec/fixtures/data_import/freshdesk/ticket_with_conversations.json').read)
  end

  before do
    account.enable_features!('data_import')
    allow(DataImports::Freshdesk::Client).to receive(:new).with(
      domain: 'acme.freshdesk.com',
      api_key: 'freshdesk-api-key'
    ).and_return(client)
    allow(client).to receive(:list_contacts).with(page: 1, per_page: 100).and_return(
      DataImports::Freshdesk::Client::Page.new(data: [contact_payload], next_page: nil)
    )
    allow(client).to receive(:list_tickets).with(page: 1, per_page: 100).and_return(
      DataImports::Freshdesk::Client::Page.new(data: [ticket_fixture.fetch('ticket')], next_page: nil)
    )
    allow(client).to receive(:retrieve_ticket).with('2001').and_return(ticket_fixture.fetch('ticket'))
    allow(client).to receive(:list_conversations).with('2001', page: 1, per_page: 100).and_return(
      DataImports::Freshdesk::Client::Page.new(data: ticket_fixture.fetch('conversations'), next_page: nil)
    )
  end

  it 'imports Freshdesk contacts, tickets, replies, and private notes through the shared importer', :aggregate_failures do
    described_class.new(data_import: data_import).perform

    contact = account.contacts.find_by!(email: 'customer@example.com')
    expect(contact).to have_attributes(
      name: 'Customer Example',
      phone_number: '+15551234567',
      identifier: 'customer-1001'
    )
    expect(contact.custom_attributes).to include(
      'freshdesk_contact_id' => '1001',
      'freshdesk_unique_external_id' => 'customer-1001'
    )

    inbox = account.inboxes.find_by!(name: 'Freshdesk Import - Email')
    expect(inbox.channel.additional_attributes).to include(
      'source_provider' => 'freshdesk',
      'source_bucket' => 'email',
      'import_placeholder' => true
    )

    conversation = account.conversations.find_by!(identifier: 'freshdesk:2001')
    expect(conversation).to have_attributes(
      status: 'resolved',
      inbox_id: inbox.id,
      contact_id: contact.id
    )
    expect(conversation.custom_attributes).to include(
      'freshdesk_ticket_id' => '2001',
      'freshdesk_status' => 4,
      'freshdesk_priority' => 2
    )

    messages = conversation.messages.order(:created_at, :id)
    expect(messages.pluck(:content)).to eq(
      [
        "Unable to finish checkout\n\nThe checkout button is not responding.",
        'Could you try this in a private window?',
        "Payments team is investigating the browser logs.\n\n[Freshdesk attachment skipped: 1]",
        'The issue still happens in a private window.'
      ]
    )
    expect(messages.map(&:message_type)).to eq(%w[incoming outgoing outgoing incoming])
    expect(messages.pluck(:private)).to eq([false, false, true, false])
    expect(messages.third.additional_attributes.dig('source', 'conversation_source')).to eq(2)
    expect(messages.third.additional_attributes.dig('source', 'attachments', 0, 'name')).to eq('browser-log.txt')

    expect(data_import.reload).to be_completed
    expect(data_import.stats).to include(
      'contacts' => include('imported' => 1, 'skipped' => 0),
      'conversations' => include('imported' => 1, 'skipped' => 0),
      'messages' => include('imported' => 4, 'skipped' => 0, 'total' => 4),
      'errors' => { 'count' => 0 }
    )
    expect(data_import.processed_records).to eq(6)
    expect(data_import.mappings.count).to eq(6)
  end

  it 'resumes a rate-limited ticket chunk from the last persisted checkpoint', :aggregate_failures do
    tickets = Array.new(3) { |index| { 'id' => index + 2001, 'source' => 1 } }
    allow(client).to receive(:list_tickets).with(page: 1, per_page: 100).and_return(
      DataImports::Freshdesk::Client::Page.new(data: tickets, next_page: nil)
    )
    importer = described_class.new(data_import: data_import)
    processed_ticket_ids = []
    rate_limited = true
    allow(importer).to receive(:import_conversation_from_summary) do |summary|
      processed_ticket_ids << summary['id']
      if summary['id'] == '2003' && rate_limited
        rate_limited = false
        raise DataImports::Freshdesk::Client::RateLimitError.new('Rate limited', retry_after: '42')
      end
    end

    expect do
      importer.import_conversations_page(starting_after: { 'page' => 1, 'offset' => 0 })
    end.to raise_error(DataImports::Freshdesk::Client::RateLimitError)
    expect(processed_ticket_ids).to eq(%w[2001 2002 2003])
    expect(data_import.reload.cursor.dig('conversations', 'starting_after')).to include('page' => 1, 'offset' => 2)

    processed_ticket_ids.clear
    result = importer.import_conversations_page(starting_after: { 'page' => 1, 'offset' => 0 })

    expect(processed_ticket_ids).to eq(%w[2003])
    expect(result).to be_done
    expect(data_import.reload.cursor['conversations']).to include('starting_after' => nil, 'completed' => true)
    expect(client).to have_received(:list_tickets).once
  end

  it 'fails with an actionable error instead of completing at the REST ticket limit', :aggregate_failures do
    tickets = Array.new(100) { |index| { 'id' => index + 1, 'source' => 1 } }
    allow(client).to receive(:list_tickets).with(page: 300, per_page: 100).and_return(
      DataImports::Freshdesk::Client::Page.new(data: tickets, next_page: nil)
    )
    importer = described_class.new(data_import: data_import)
    processed_ticket_ids = []
    allow(importer).to receive(:import_conversation_from_summary) { |summary| processed_ticket_ids << summary['id'] }
    limit_error = nil

    expect do
      importer.import_conversations_page(starting_after: { 'page' => 300, 'offset' => 90 })
    end.to raise_error(DataImports::Freshdesk::TicketLimitError) { |error| limit_error = error }
    importer.fail!(limit_error)

    expect(processed_ticket_ids).to eq((91..100).map(&:to_s))
    expect(data_import.reload).to be_failed
    expect(data_import.cursor.dig('conversations', 'starting_after')).to include('page' => 300, 'offset' => 99)
    expect(data_import.import_errors.last).to have_attributes(
      error_code: 'DataImports::Freshdesk::TicketLimitError',
      message: limit_error.message
    )
    expect(data_import.import_errors.last.details).to include(
      'kind' => 'run_error',
      'source_provider' => 'freshdesk',
      'error_class' => 'DataImports::Freshdesk::TicketLimitError'
    )
  end
end
