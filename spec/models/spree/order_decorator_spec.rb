require 'spec_helper'

describe Spree::Order do
  let(:product_id) { 777 }
  let(:quantity) { 3 }
  let(:tube) { Class.new(Array) { alias :post :push }.new }

  let(:almost_complete_order) {
    Spree::Order.new.tap do |order|
      product = Spree::Product.new(id: product_id)
      line_item =
        Spree::LineItem.new(
          variant: Spree::Variant.new(product: product),
          price: 117.20,
          quantity: quantity,
          currency: 'USD')
        line_item.inventory_units += 10.times.map { Spree::InventoryUnit.new }

        order.line_items << line_item
        order.save!

        order.email = 'test@mailinator.com'
        order.state = 'confirm'
        allow(order).to receive(:insufficient_stock_lines).and_return([])
    end
  }

  it 'should notify about purchase' do
    allow(almost_complete_order).to receive(:with_order_notification_tube) do |&block|
      block.(tube)
    end

    expect(almost_complete_order.next).to eq true

    expect(tube).to eq [{
      product_id: product_id,
      quantity: quantity
    }.to_json]
  end
end
