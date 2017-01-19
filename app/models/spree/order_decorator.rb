require 'beaneater'

Spree::Order.class_eval do
  def decrease_quantity_in_core
    with_order_notification_tube do |tube|
      line_items.each do |li|
        tube.put({ product_id: li.product.id, quantity: li.quantity }.to_json)
      end
    end
  end

  private

  # :nocov: external service invocation
  def with_order_notification_tube
    beanstalk = Beaneater.new(ENV.fetch('ORDER_NOTIFICAION_BEANSTALKD_URL'))
    begin
      tube = beanstalk.tubes[ENV.fetch('ORDER_NOTIFICAION_TUBE')]
      yield(tube)
    ensure
      beanstalk.close
    end
  end
  # :nocov:
end

Spree::Order.state_machine.after_transition to: :complete,
                                            do: :decrease_quantity_in_core
