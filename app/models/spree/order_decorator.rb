require 'iron_mq'

Spree::Order.class_eval do
  def decrease_quantity_in_core
    with_order_notification_tube do |tube|
      line_items.each do |li|
        tube.post({ product_id: li.product.id, quantity: li.quantity }.to_json)
      end
    end
  end

  private

  # :nocov: external service invocation
  def with_order_notification_tube
    ironmq = IronMQ::Client.new
    queue = ironmq.queue('spree-order-notification')
    yield(queue)
  end
  # :nocov:
end

Spree::Order.state_machine.after_transition to: :complete,
                                            do: :decrease_quantity_in_core
