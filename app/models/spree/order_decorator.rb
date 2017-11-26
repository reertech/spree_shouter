require 'bunny'

Spree::Order.class_eval do
  def decrease_quantity_in_core
    rabbit_host, exchange, routing_key = ENV['RABBIT_HOST'], ENV['RABBIT_EXCHANGE'], ENV['RABBIT_ROUTING_KEY']
    return warn('You need to configure shouter') if rabbit_host.nil? || exchange.nil? || routing_key.nil?

    with_connection(rabbit_host, exchange, routing_key) do
      payload(self)
    end
  end

  private

  def payload(order)
    MQOrderSerializer.serialize(order).to_json
  end

  def with_connection(rabbit_host, exchange, routing_key) # :nocov: external service invocation
    connection = Bunny.new(rabbit_host)
    connection.start
    channel  = connection.create_channel
    exchange = channel.topic(exchange, durable: true)
    exchange.publish(yield, routing_key: routing_key, persistent: true)
    connection.close
  end
end

class MQOrderSerializer
  class << self
    def serialize(order)
      {
        id: order.id,
        shipping_total: order.shipment_total.to_f,
        line_items: order.line_items.map { |l| line_item(l) }
      }
    end

    private

    def line_item(line_item)
      product = line_item.product
      {
        id: line_item.id,
        product_id: product && product.id,
        title: product && product.name,
        quantity: line_item.quantity,
        price: line_item.price.to_f,
        total: line_item.total.to_f
      }
    end
  end
end

Spree::Order.state_machine.after_transition to: :complete,
                                            do: :decrease_quantity_in_core
