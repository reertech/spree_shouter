require 'beaneater'
Spree::Order.class_eval do
  def decrease_quantity_in_core
    beanstalk = Beaneater.new('localhost:11300')
    tube = beanstalk.tubes["tube"]

    self.line_items.each do |li|
      tube.put({product_id: li.product.id, quantity: li.quantity}.to_json)
    end

    beanstalk.close
  end
end

Spree::Order.state_machine.after_transition to: :complete,
                                            do: :decrease_quantity_in_core
