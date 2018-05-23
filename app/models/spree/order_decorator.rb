require 'bunny'

Spree::Order.class_eval do
  def decrease_quantity_in_core
    rabbit_host, exchange, routing_key = ENV['RABBIT_HOST'], ENV['RABBIT_EXCHANGE'], ENV['RABBIT_ROUTING_KEY']
    return warn('You need to configure shouter') if rabbit_host.nil? || exchange.nil? || routing_key.nil?

    with_connection(rabbit_host, exchange, routing_key) do
      payload(self)
    end
  end

  def send_userinfo_to_crm
    host = ENV['CRM_HOST']
    port = ENV['CRM_PORT'] || 80
    return warn('Define CRM_HOST to environment variable to submit order information to CRM.') if host.nil?
    begin
      http = Net::HTTP.new(host, port)

      search_path = "/api/users?q=#{self.email}"
      search_response = http.send_request('GET', search_path)

      json_response = JSON.parse(search_response.body)
      user_id = (json_response.any? ? json_response.first['id'] : SecureRandom.uuid)

      path = "/api/users/#{user_id}?#{UserInfoSerializer.user_info_serializer(self).to_query}"
      response = http.send_request('PUT', path)
      puts response.body
    rescue StandardError => e
      puts e.message
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
        total: order.total.to_f,
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

class UserInfoSerializer
  class << self
    def user_info_serializer(order)
      if user = order.user
        {
          email: user.email,
          first_name: user.first_name ? user.first_name : order.billing_address.first_name,
          last_name: user.last_name ? user.last_name : order.billing_address.last_name,
          website_url: user.website_url,
          google_plus_url: user.google_plus_url,
          bio_info: user.bio_info,
          birthdate: user.birthdate.strftime('%Y-%m-%d'),
          anniversary_date: user.anniversary_date.strftime('%Y-%m-%d')
        }
      else
        b_address = order.billing_address
        {
          email: order.email,
          first_name: b_address.first_name,
          last_name: b_address.last_name
        }
      end
    end
  end
end

Spree::Order.state_machine.after_transition to: :complete,
                                            do: :decrease_quantity_in_core
Spree::Order.state_machine.after_transition to: :complete,
                                            do: :send_userinfo_to_crm
