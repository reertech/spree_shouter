require 'spec_helper'

describe Spree::Order do
  let(:quantity) { 3 }
  let(:product) { FactoryGirl.create(:product) }
  let(:line_item) do
    Spree::LineItem.new(
      variant: FactoryGirl.create(:variant, product: product),
      price: 117.20,
      quantity: quantity,
      currency: 'USD'
    )
  end

  let(:almost_complete_order) {
    Spree::Order.new.tap do |order|
      line_item.inventory_units += 10.times.map { Spree::InventoryUnit.new }
      order.line_items << line_item
      order.save!

      order.email = 'test@mailinator.com'
      order.state = 'confirm'
      allow(order).to receive(:insufficient_stock_lines).and_return([])
    end
  }

  before do
    ENV['RABBIT_HOST'] = 'amqp:host'
    ENV['RABBIT_EXCHANGE'] = 'exchange'
    ENV['RABBIT_ROUTING_KEY'] = 'routing_key'
  end

  it 'should notify about purchase' do
    expect(almost_complete_order).to receive(:with_connection)
      .with('amqp:host', 'exchange', 'routing_key')

    expect(almost_complete_order.next).to eq true
  end

  it 'should serialize order' do
    expect(MQOrderSerializer.serialize(almost_complete_order)).to eq({
      id: almost_complete_order.id,
      shipping_total: 0.0,
      total: 0.0,
      line_items: [{
        id: line_item.id,
        product_id: product.id,
        title: product.name,
        quantity: quantity,
        price: 117.2,
        total: 351.6
      }]
    })
  end
end
