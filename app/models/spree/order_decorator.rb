require 'bunny'

module Spree
  module OrderDecorator
    def decrease_quantity_in_core
      with_https { payload(self) }

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
        raise response.message unless response.code == '200'
        puts response.body
      rescue StandardError => e
        Raven.capture_exception(e) if defined?(Raven)
        puts e.message
      end
    end

    private

    def payload(order)
      MQOrderSerializer.serialize(order).to_json
    end

    def with_connection(rabbit_host, exchange, routing_key)
      # :nocov: external service invocation
      connection = Bunny.new(rabbit_host)
      connection.start
      channel = connection.create_channel
      exchange = channel.topic(exchange, durable: true)
      exchange.publish(yield, routing_key: routing_key, persistent: true)
      connection.close
    end

    def with_https
      core_url = ENV['CORE_API_ORDERS_URL']
      return warn('Define CORE_API_ORDERS_URL to environment variable to submit order information.') if core_url.nil?

      response = Net::HTTP.post URI(core_url),
                                yield,
                                'Content-Type' => 'application/json'
      raise response.message unless response.code == '200'
      puts response.body
    rescue StandardError => e
      Raven.capture_exception(e) if defined?(Raven)
      puts e.message
    end
  end
end

::Spree::Order.prepend(Spree::OrderDecorator)

class MQOrderSerializer
  class << self
    def serialize(order)
      {
        id: order.id,
        number: order.number.presence.to_s,
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
      address = order.billing_address
      full_address = [address.first_name, address.last_name, address.address1,
                      address.address2, address.city, address.state&.name, address.zipcode,
                      address.country&.name].reject(&:blank?).map(&:strip).join(' ')
      if user = order.user
        {
          email: user.email,
          first_name: user.first_name ? user.first_name : address.first_name,
          last_name: user.last_name ? user.last_name : address.last_name,
          phone: address.phone,
          address: full_address,
          birthdate: user.birthdate.strftime('%Y-%m-%d'),
          anniversary_date: user.anniversary_date.strftime('%Y-%m-%d')
        }
      else
        {
          email: order.email,
          first_name: address.first_name,
          last_name: address.last_name,
          phone: address.phone,
          address: full_address
        }
      end
    end
  end
end

Spree::Order.state_machine.after_transition to: :complete,
                                            do: :decrease_quantity_in_core
Spree::Order.state_machine.after_transition to: :complete,
                                            do: :send_userinfo_to_crm
